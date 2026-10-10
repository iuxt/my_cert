"""Integration tests using real OpenSSL/LibreSSL and isolated certificate stores."""

import concurrent.futures
import ipaddress
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1]
PASSWORD = "test-password\ntest-password\n"


class CertificateScriptsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="my cert tests ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / "repository with spaces"
        self.repo.mkdir()
        for source in [*SOURCE.glob("*.sh"), SOURCE / "openssl.cnf"]:
            shutil.copy2(source, self.repo / source.name)
        self.env = {**os.environ, "OPENSSL": self.openssl}

    def command(self, args, *, input="", success=True, env=None):
        result = subprocess.run(
            [str(arg) for arg in args], cwd=self.root, env=env or self.env,
            input=input, text=True, capture_output=True, timeout=30,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def script(self, name, *args, **kwargs):
        return self.command([self.repo / name, *args], **kwargs)

    def crypto(self, *args, **kwargs):
        return self.command([self.openssl, *args], **kwargs)

    def issue(self, name="test.example.com"):
        self.script("mk_ca.sh")
        self.script("mk_cert.sh", name, input=PASSWORD)

    def verify(self, name="test.example.com", *, revoked=False, purpose=None):
        args = ["verify", "-x509_strict", "-CAfile", self.repo / "ca/ca.crt"]
        if revoked:
            args += ["-crl_check", "-CRLfile", self.repo / "ca/crl.pem"]
        if purpose:
            args += ["-purpose", purpose]
        args += [self.repo / f"ssl/{name}.crt"]
        return self.crypto(*args, success=not revoked)

    def failure_env(self, command, argument=""):
        wrapper = self.root / "failing openssl"
        wrapper.write_text("""#!/bin/sh
if [ "$1" = "$FAIL_COMMAND" ]; then
    match=0
    if [ -z "$FAIL_ARGUMENT" ]; then match=1; fi
    for argument do
        if [ "$argument" = "$FAIL_ARGUMENT" ]; then match=1; fi
    done
    if [ "$match" -eq 1 ]; then
        while [ "$#" -gt 1 ]; do
            if [ "$1" = -out ]; then
                printf 'partial output' > "$2"
                break
            fi
            shift
        done
        exit 42
    fi
fi
exec "$REAL_OPENSSL" "$@"
""")
        wrapper.chmod(0o700)
        return {
            **self.env, "OPENSSL": str(wrapper), "REAL_OPENSSL": self.openssl,
            "FAIL_COMMAND": command, "FAIL_ARGUMENT": argument,
        }

    def assert_no_temporary_files(self):
        self.assertFalse(list(self.repo.glob("*/.tmp.*")))

    def test_strict_certificates_permissions_and_repeat_execution(self):
        self.issue()
        self.verify(purpose="sslserver")
        self.verify(purpose="sslclient")
        # Also validate LibreSSL output with the default OpenSSL verifier.
        self.command([
            shutil.which("openssl"), "verify", "-x509_strict",
            "-CAfile", self.repo / "ca/ca.crt", self.repo / "ssl/test.example.com.crt",
        ])
        for hostname in ["test.example.com", "child.test.example.com", "localhost"]:
            self.command([
                shutil.which("openssl"), "verify", "-verify_hostname", hostname,
                "-CAfile", self.repo / "ca/ca.crt", self.repo / "ssl/test.example.com.crt",
            ])
        self.command([
            shutil.which("openssl"), "verify", "-verify_ip", "127.0.0.1",
            "-CAfile", self.repo / "ca/ca.crt", self.repo / "ssl/test.example.com.crt",
        ])
        files = ["ca/ca.key", "ca/ca.crt", "ssl/test.example.com.key",
                 "ssl/test.example.com.crt", "ssl/test.example.com.p12"]
        before = {name: (self.repo / name).read_bytes() for name in files}
        self.script("mk_ca.sh")
        repeated = self.script("mk_cert.sh", "test.example.com")
        self.assertNotIn("Enter Export Password", repeated.stderr)
        for name in files:
            self.assertEqual((self.repo / name).read_bytes(), before[name])
        for name in ["ca/ca.key", "ssl/test.example.com.key", "ssl/test.example.com.p12"]:
            path = self.repo / name
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            path.chmod(0o644)
        self.script("mk_cert.sh", "test.example.com")
        for name in ["ca/ca.key", "ssl/test.example.com.key", "ssl/test.example.com.p12"]:
            self.assertEqual(stat.S_IMODE((self.repo / name).stat().st_mode), 0o600)
        self.crypto("pkcs12", "-in", self.repo / "ssl/test.example.com.p12",
                    "-noout", "-passin", "pass:test-password")
        self.assert_no_temporary_files()

    def test_missing_ca_and_invalid_arguments_fail_without_keys(self):
        self.script("mk_cert.sh", "test.example.com", success=False)
        for name in ["mk_cert.sh", "revoke.sh"]:
            self.script(name, success=False)
            self.script(name, "../escaped", success=False)
            self.script(name, "test,IP:10.0.0.1", success=False)
        self.script("update_crl.sh", success=False)
        self.assertFalse(list(self.repo.rglob("*.key")))
        self.assert_no_temporary_files()

    def test_ca_generation_failure_and_retry(self):
        self.script("mk_ca.sh", env=self.failure_env("ecparam"), success=False)
        self.assertFalse((self.repo / "ca/ca.key").exists())
        self.assert_no_temporary_files()
        self.script("mk_ca.sh", env=self.failure_env("req", "-x509"), success=False)
        self.assertFalse((self.repo / "ca/ca.crt").exists())
        self.assert_no_temporary_files()
        self.script("mk_ca.sh")

    def test_partial_certificate_is_repaired_after_signing_failure(self):
        self.script("mk_ca.sh")
        (self.repo / "ssl").mkdir()
        cert = self.repo / "ssl/test.example.com.crt"
        cert.write_text("partial legacy certificate")
        self.script("mk_cert.sh", "test.example.com", input=PASSWORD,
                    env=self.failure_env("x509", "-req"), success=False)
        self.assertEqual(cert.read_text(), "partial legacy certificate")
        self.assert_no_temporary_files()
        self.script("mk_cert.sh", "test.example.com", input=PASSWORD)
        self.verify()

    def test_empty_csr_certificate_and_p12_are_repaired(self):
        self.issue()
        key_before = (self.repo / "ssl/test.example.com.key").read_bytes()
        for suffix in ["csr", "crt", "p12"]:
            (self.repo / f"ssl/test.example.com.{suffix}").write_bytes(b"")
        self.script("mk_cert.sh", "test.example.com", input=PASSWORD)
        self.verify()
        self.assertEqual((self.repo / "ssl/test.example.com.key").read_bytes(), key_before)
        self.crypto("pkcs12", "-in", self.repo / "ssl/test.example.com.p12",
                    "-noout", "-passin", "pass:test-password")
        # An empty P12 alone must not be mistaken for a complete export.
        (self.repo / "ssl/test.example.com.p12").write_bytes(b"")
        self.script("mk_cert.sh", "test.example.com", input=PASSWORD)
        self.assertGreater((self.repo / "ssl/test.example.com.p12").stat().st_size, 0)

    def test_failed_p12_export_does_not_publish_certificate(self):
        self.script("mk_ca.sh")
        self.script("mk_cert.sh", "test.example.com", input="one\ntwo\n", success=False)
        self.assertFalse((self.repo / "ssl/test.example.com.crt").exists())
        self.assertFalse((self.repo / "ssl/test.example.com.p12").exists())
        self.assert_no_temporary_files()
        self.script("mk_cert.sh", "test.example.com", input=PASSWORD)
        self.verify()

    def test_revocation_and_failed_crl_update_preserve_old_crl(self):
        self.issue()
        crl = self.repo / "ca/crl.pem"
        before = crl.read_bytes()
        self.script("update_crl.sh", env=self.failure_env("ca", "-gencrl"), success=False)
        self.assertEqual(crl.read_bytes(), before)
        self.assert_no_temporary_files()
        self.script("revoke.sh", "test.example.com")
        result = self.verify(revoked=True)
        self.assertIn("certificate revoked", result.stdout + result.stderr)
        self.script("update_crl.sh")
        self.verify(revoked=True)

    def test_optional_crl_deployment_and_reload_arguments(self):
        self.script("mk_ca.sh")
        self.script("update_crl.sh")
        marker = self.root / "reload marker"
        reload_script = self.root / "reload command"
        reload_script.write_text('#!/bin/sh\nprintf "%s\\n" "$2" > "$1"\n')
        reload_script.chmod(0o700)
        destination = self.root / "deployed CRL.pem"
        self.script("update_crl.sh", destination, reload_script, marker, "two words")
        self.assertEqual(destination.read_bytes(), (self.repo / "ca/crl.pem").read_bytes())
        self.assertEqual(marker.read_text(), "two words\n")
        marker.unlink()
        self.script("update_crl.sh", self.root / "missing/crl.pem",
                    reload_script, marker, "must not run", success=False)
        self.assertFalse(marker.exists())
        self.script("update_crl.sh", destination, "false", success=False)

    def test_existing_ca_without_extensions_is_preserved(self):
        self.script("mk_ca.sh")
        key_before = (self.repo / "ca/ca.key").read_bytes()
        legacy_config = self.root / "legacy.cnf"
        legacy_config.write_text("[req]\ndistinguished_name=dn\n[dn]\n")
        self.crypto("req", "-x509", "-new", "-days", "30", "-config", legacy_config,
                    "-subj", "/CN=iuxt Root CA", "-key", self.repo / "ca/ca.key",
                    "-out", self.repo / "ca/ca.crt")
        cert_before = (self.repo / "ca/ca.crt").read_bytes()
        self.script("mk_ca.sh", success=False)
        self.script("mk_cert.sh", "test.example.com", success=False)
        self.assertEqual((self.repo / "ca/ca.key").read_bytes(), key_before)
        self.assertEqual((self.repo / "ca/ca.crt").read_bytes(), cert_before)

    def test_missing_private_key_does_not_replace_existing_identity(self):
        self.issue()
        cert_before = (self.repo / "ssl/test.example.com.crt").read_bytes()
        (self.repo / "ssl/test.example.com.key").unlink()
        self.script("mk_cert.sh", "test.example.com", success=False)
        self.assertFalse((self.repo / "ssl/test.example.com.key").exists())
        self.assertEqual((self.repo / "ssl/test.example.com.crt").read_bytes(), cert_before)
        (self.repo / "ca/ca.key").unlink()
        self.script("mk_ca.sh", success=False)
        self.assertFalse((self.repo / "ca/ca.key").exists())

    def test_ca_regeneration_preserves_key_and_revocation_database(self):
        self.issue()
        self.script("revoke.sh", "test.example.com")
        key_before = (self.repo / "ca/ca.key").read_bytes()
        database_before = (self.repo / "ca/index.txt").read_bytes()
        (self.repo / "ca/ca.crt").unlink()
        (self.repo / "ca/crl.pem").unlink()
        self.script("mk_ca.sh")
        self.assertEqual((self.repo / "ca/ca.key").read_bytes(), key_before)
        self.assertEqual((self.repo / "ca/index.txt").read_bytes(), database_before)
        self.verify(revoked=True)

    def test_legacy_leaf_certificate_requires_explicit_migration(self):
        self.issue()
        key_before = (self.repo / "ssl/test.example.com.key").read_bytes()
        legacy_extensions = self.root / "legacy-extensions.cnf"
        legacy_extensions.write_text("subjectAltName=DNS:test.example.com\n")
        self.crypto(
            "x509", "-req", "-days", "30", "-set_serial", "0x1234",
            "-CA", self.repo / "ca/ca.crt", "-CAkey", self.repo / "ca/ca.key",
            "-extfile", legacy_extensions, "-in", self.repo / "ssl/test.example.com.csr",
            "-out", self.repo / "ssl/test.example.com.crt",
        )
        cert_before = (self.repo / "ssl/test.example.com.crt").read_bytes()
        self.script("mk_cert.sh", "test.example.com", success=False)
        self.assertEqual((self.repo / "ssl/test.example.com.crt").read_bytes(), cert_before)
        (self.repo / "ssl/test.example.com.crt").unlink()
        (self.repo / "ssl/test.example.com.p12").unlink()
        self.script("mk_cert.sh", "test.example.com", input=PASSWORD)
        self.verify()
        self.assertEqual((self.repo / "ssl/test.example.com.key").read_bytes(), key_before)

    def test_parallel_issuance_uses_distinct_serials(self):
        self.script("mk_ca.sh")
        names = [f"parallel{i}.example.com" for i in range(8)]
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(
                lambda name: self.script("mk_cert.sh", name, input=PASSWORD), names,
            ))
        self.assertEqual(len(results), len(names))
        serials = []
        for name in names:
            self.verify(name)
            serials.append(self.crypto(
                "x509", "-in", self.repo / f"ssl/{name}.crt", "-noout", "-serial",
            ).stdout.strip())
        self.assertEqual(len(set(serials)), len(names))
        self.assert_no_temporary_files()

    def test_usernames_have_cn_without_dns_san(self):
        self.script("mk_ca.sh")
        for name,options in [
            ("user_name", []), ("zhangsan", []),
            ("user_name.with.dots", []), ("john.doe", ["--client"]),
        ]:
            self.script("mk_cert.sh", *options, name, input=PASSWORD)
            cert_text = self.crypto("x509", "-in", self.repo / f"ssl/{name}.crt",
                                    "-noout", "-text").stdout
            csr_text = self.crypto("req", "-in", self.repo / f"ssl/{name}.csr",
                                   "-noout", "-text").stdout
            self.assertNotIn("X509v3 Subject Alternative Name:", cert_text)
            self.assertNotIn("X509v3 Subject Alternative Name:", csr_text)
            subject = self.crypto("x509", "-in", self.repo / f"ssl/{name}.crt",
                                  "-noout", "-subject").stdout
            self.assertIn(name, subject)
            self.verify(name, purpose="sslclient")
            self.script("mk_cert.sh", *options, name)
        self.script("revoke.sh", "user_name")
        self.verify("user_name", revoked=True)

    def test_ipv4_and_ipv6_san_match_ip_addresses(self):
        self.script("mk_ca.sh")
        for address in ["192.0.2.1", "2001:db8::1", "::1", "::ffff:192.0.2.1"]:
            self.script("mk_cert.sh", address, input=PASSWORD)
            self.command([
                shutil.which("openssl"), "verify", "-x509_strict", "-verify_ip", address,
                "-CAfile", self.repo / "ca/ca.crt", self.repo / f"ssl/{address}.crt",
            ])
            self.command([
                shutil.which("openssl"), "verify", "-verify_ip", "192.0.2.2",
                "-CAfile", self.repo / "ca/ca.crt", self.repo / f"ssl/{address}.crt",
            ], success=False)
            for tool,extension in [("x509", "crt"), ("req", "csr")]:
                text = self.crypto(tool, "-in", self.repo / f"ssl/{address}.{extension}",
                                   "-noout", "-text").stdout
                self.assertIn("IP Address:", text)
                self.assertNotIn(f"DNS:{address}", text)
                self.assertNotIn(f"DNS:*.{address}", text)
            self.script("mk_cert.sh", address)
        self.script("revoke.sh", "2001:db8::1")
        self.verify("2001:db8::1", revoked=True)

    def test_single_label_server_name_can_be_explicit(self):
        self.script("mk_ca.sh")
        for name,options in [("intranet", ["--server"]), ("localhost", [])]:
            self.script("mk_cert.sh", *options, name, input=PASSWORD)
            self.command([
                shutil.which("openssl"), "verify", "-verify_hostname", name,
                "-CAfile", self.repo / "ca/ca.crt", self.repo / f"ssl/{name}.crt",
            ])
            self.script("mk_cert.sh", *options, name)

    def test_invalid_dns_and_ip_inputs_are_rejected_before_creating_keys(self):
        self.script("mk_ca.sh")
        for name in [
            "user_name", "bad_domain.example", "a..example", "a.-bad.example",
            "a.bad-.example", "a" * 64 + ".example", ".".join(["a" * 63] * 4),
            "192.0.2.999", "01.2.3.4", "1.2.3", "1.2.3.4.5", "2001:db8::g",
            "1::2::3", ":::1", "1:2:3:4:5:6:7:8:9", "fe80::1%en0", "[::1]",
        ]:
            self.script("mk_cert.sh", "--server", name, success=False)
        self.assertFalse(list(self.repo.glob("ssl/*.key")))
        self.assert_no_temporary_files()

    def test_changing_client_identity_to_server_requires_reissue(self):
        self.script("mk_ca.sh")
        self.script("mk_cert.sh", "--client", "john.doe", input=PASSWORD)
        key_before = (self.repo / "ssl/john.doe.key").read_bytes()
        cert_before = (self.repo / "ssl/john.doe.crt").read_bytes()
        result = self.script("mk_cert.sh", "--server", "john.doe", success=False)
        self.assertIn("SAN", result.stderr)
        self.assertEqual((self.repo / "ssl/john.doe.crt").read_bytes(), cert_before)
        (self.repo / "ssl/john.doe.crt").unlink()
        (self.repo / "ssl/john.doe.p12").unlink()
        self.script("mk_cert.sh", "--server", "john.doe", input=PASSWORD)
        self.assertEqual((self.repo / "ssl/john.doe.key").read_bytes(), key_before)
        self.command([
            shutil.which("openssl"), "verify", "-verify_hostname", "john.doe",
            "-CAfile", self.repo / "ca/ca.crt", self.repo / "ssl/john.doe.crt",
        ])

    def test_ip_parser_matches_standard_library(self):
        for value in [
            "0.0.0.0", "255.255.255.255", "192.0.2.1", "192.0.2.999", "01.2.3.4",
            "1.2.3", "::", "::1", "2001:db8::1", "2001:db8:0:0:0:0:0:1",
            "::ffff:192.0.2.1", "2001:db8::192.0.2.1", "1:2:3:4:5:6:7:8",
            "1:2:3:4:5:6:192.0.2.1", "1:2:3:4:5:6::192.0.2.1", "1:2:3:4:5:6:7",
            "1:2:3:4:5:6:7:8:9", "1::2::3", ":::1", "2001:db8::g", "[::1]",
        ]:
            try:
                ipaddress.ip_address(value)
                valid = True
            except ValueError:
                valid = False
            self.command([
                "sh", "-c", '. "$1/common.sh"; is_ip_address "$2"',
                "sh", self.repo, value,
            ], success=valid)

    def test_legacy_username_and_ip_san_need_explicit_reissue(self):
        self.script("mk_ca.sh")
        for index,name in enumerate(["user_name", "192.0.2.1"]):
            self.script("mk_cert.sh", name, input=PASSWORD)
            key_before = (self.repo / f"ssl/{name}.key").read_bytes()
            legacy_config = self.root / "legacy-san.cnf"
            legacy_config.write_text((self.repo / "openssl.cnf").read_text() +
                f"\n[SAN]\nsubjectAltName=DNS:{name}\n"
                f"\n[usr_cert]\nsubjectAltName=DNS:{name}\n")
            self.crypto("req", "-new", "-subj", f"/CN={name}", "-reqexts", "SAN",
                        "-config", legacy_config, "-key", self.repo / f"ssl/{name}.key",
                        "-out", self.repo / f"ssl/{name}.csr")
            self.crypto(
                "x509", "-req", "-days", "30", "-set_serial", str(1000 + index),
                "-CA", self.repo / "ca/ca.crt", "-CAkey", self.repo / "ca/ca.key",
                "-extfile", legacy_config, "-extensions", "usr_cert",
                "-in", self.repo / f"ssl/{name}.csr", "-out", self.repo / f"ssl/{name}.crt",
            )
            before = {suffix: (self.repo / f"ssl/{name}.{suffix}").read_bytes()
                      for suffix in ["csr", "crt", "p12"]}
            result = self.script("mk_cert.sh", name, success=False)
            self.assertIn("SAN", result.stderr)
            for suffix in before:
                self.assertEqual((self.repo / f"ssl/{name}.{suffix}").read_bytes(), before[suffix])
            (self.repo / f"ssl/{name}.crt").unlink()
            (self.repo / f"ssl/{name}.p12").unlink()
            self.script("mk_cert.sh", name, input=PASSWORD)
            self.assertEqual((self.repo / f"ssl/{name}.key").read_bytes(), key_before)
            for tool,extension in [("x509", "crt"), ("req", "csr")]:
                text = self.crypto(tool, "-in", self.repo / f"ssl/{name}.{extension}",
                                   "-noout", "-text").stdout
                if name == "user_name":
                    self.assertNotIn("X509v3 Subject Alternative Name:", text)
                else:
                    self.assertNotIn(f"DNS:{name}", text)
            self.verify(name)


def load_tests(loader, tests, pattern):
    suite = unittest.TestSuite()
    versions = set()
    for candidate in [os.environ.get("OPENSSL"), shutil.which("openssl"), "/usr/bin/openssl"]:
        if not candidate or not Path(candidate).is_file():
            continue
        version = subprocess.check_output([candidate, "version"], text=True).strip()
        if version in versions:
            continue
        versions.add(version)
        name = "_".join(version.split()[:2]).replace(".", "_") + "Tests"
        backend_tests = type(name, (CertificateScriptsTests,), {"openssl": candidate})
        suite.addTests(loader.loadTestsFromTestCase(backend_tests))
    if not versions:
        raise RuntimeError("No OpenSSL/LibreSSL executable found")
    return suite


if __name__ == "__main__":
    unittest.main()
