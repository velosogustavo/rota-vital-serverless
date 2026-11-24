"""Testes do handler sem Docker: python3 -m unittest discover tests"""
import json
import pathlib
import sys
import unittest

RAIZ = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "hello_world"))
import app  # noqa: E402


def evento(nome):
    return json.loads((RAIZ / "events" / f"{nome}.json").read_text())


class TestGuia(unittest.TestCase):
    def setUp(self):
        app.contador = 0

    def test_evento_base64_gera_guia(self):
        r = app.lambda_handler(evento("pedido"), None)
        self.assertEqual(r["statusCode"], 201)
        guia = json.loads(r["body"])
        self.assertEqual(guia["guia"], "G-R-001")
        self.assertEqual(guia["hospital"], "H-Recife")
        self.assertEqual(guia["bolsas"], ["O-NEG-0142"])

    def test_body_texto_como_no_start_api(self):
        r = app.lambda_handler({"body": '{"requisicaoId":"R-002","hospital":"H-Caruaru"}'}, None)
        self.assertEqual(r["statusCode"], 201)
        self.assertEqual(json.loads(r["body"])["bolsas"], [])

    def test_contador_cresce_no_mesmo_ambiente(self):
        for esperado in (1, 2, 3):
            r = app.lambda_handler({"body": '{"requisicaoId":"R-002"}'}, None)
            self.assertEqual(json.loads(r["body"])["invocacaoNesteAmbiente"], esperado)

    def test_sem_requisicao_id(self):
        r = app.lambda_handler(evento("pedido-invalido"), None)
        self.assertEqual(r["statusCode"], 400)

    def test_json_invalido(self):
        r = app.lambda_handler({"body": "isso nao e json"}, None)
        self.assertEqual(r["statusCode"], 400)


if __name__ == "__main__":
    unittest.main()
