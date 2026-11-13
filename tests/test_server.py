import unittest

from server import resolve_model


class ResolveModelTests(unittest.TestCase):
    def test_prefers_exact_requested_tag(self):
        installed = {"llama3.1:8b", "llama3.1:8b-instruct-q4_K_M"}
        self.assertEqual(resolve_model(installed), "llama3.1:8b")

    def test_accepts_installed_quantized_variant(self):
        installed = {"llama3.1:8b-instruct-q4_K_M"}
        self.assertEqual(resolve_model(installed), "llama3.1:8b-instruct-q4_K_M")

    def test_rejects_unrelated_models(self):
        self.assertIsNone(resolve_model({"gemma3:4b"}))


if __name__ == "__main__":
    unittest.main()
