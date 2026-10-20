import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class SentinelArtifactTests(unittest.TestCase):
    def test_alert_examples_have_contract_fields_and_all_severities(self):
        schema = json.loads(
            (ROOT / "alert-contract" / "normalized-alert.schema.json").read_text()
        )
        examples = json.loads(
            (ROOT / "samples" / "normalized-alerts.json").read_text()
        )
        required = set(schema["required"])

        self.assertEqual(
            {example["severity"] for example in examples},
            {"low", "medium", "high", "critical"},
        )
        for example in examples:
            self.assertTrue(required.issubset(example))
            self.assertIsNone(example["resource_id"])
            self.assertTrue(example["evidence"]["simulation"])
            self.assertIsNone(example["sentinel"]["system_alert_id"])

    def test_waf_fixture_has_distinct_synthetic_transactions(self):
        events = json.loads((ROOT / "samples" / "waf-firewall-events.json").read_text())

        self.assertEqual(len(events), 6)
        self.assertEqual({event["ClientIp"] for event in events}, {"192.0.2.20"})
        self.assertEqual({event["Action"] for event in events}, {"Blocked"})
        self.assertEqual(len({event["TransactionId"] for event in events}), 6)
        self.assertTrue(
            all("Synthetic test event" in event["Message"] for event in events)
        )

    def test_detection_queries_are_labeled_and_use_documented_tables(self):
        query_dir = ROOT / "queries"
        queries = {
            path.name: path.read_text()
            for path in query_dir.glob("*.kql")
        }
        self.assertEqual(
            set(queries),
            {
                "waf-repeated-blocks.kql",
                "waf-rate-limit.kql",
                "entra-repeated-failed-signins.kql",
                "entra-single-failure-demo.kql",
                "defender-cloud-alerts.kql",
                "azure-activity-repeated-failures.kql",
                "azure-activity-repeated-failures-demo.kql",
                "waf-repeated-blocks-demo.kql",
                "entra-repeated-failed-signins-demo.kql",
            },
        )
        self.assertIn("AGWFirewallLogs", queries["waf-repeated-blocks.kql"])
        self.assertIn("RateLimitRuleId", queries["waf-rate-limit.kql"])
        self.assertIn("SigninLogs", queries["entra-repeated-failed-signins.kql"])
        self.assertIn(
            "REPLACE_WITH_APPROVED_TEST_ACCOUNT_UPN",
            queries["entra-single-failure-demo.kql"],
        )
        self.assertIn("SecurityAlert", queries["defender-cloud-alerts.kql"])
        self.assertIn(
            "AzureActivity", queries["azure-activity-repeated-failures.kql"]
        )
        self.assertIn(
            "FailedOperationCount >= 5",
            queries["azure-activity-repeated-failures.kql"],
        )
        self.assertTrue(
            all("not" in text.lower() and "live" in text.lower() for text in queries.values())
        )

    def test_standalone_demo_queries_have_no_live_table_dependencies(self):
        demo_queries = {
            "azure-activity-repeated-failures-demo.kql": (
                "FailedOperationCount >= 5",
                "FailedOperationCount",
            ),
            "waf-repeated-blocks-demo.kql": (
                "blockedTransactions >= 5",
                "blockedTransactions",
            ),
            "entra-repeated-failed-signins-demo.kql": (
                "failures >= 10",
                "affectedAccounts",
            ),
        }
        live_tables = ("AzureActivity", "AGWFirewallLogs", "SigninLogs")
        for name, expected in demo_queries.items():
            with self.subTest(query=name):
                query = (ROOT / "queries" / name).read_text()
                executable_query = "\n".join(
                    line
                    for line in query.splitlines()
                    if not line.lstrip().startswith("//")
                )
                self.assertIn("datatable(", executable_query)
                self.assertIn("Simulation = true", executable_query)
                self.assertNotIn("join ", executable_query.lower())
                for table in live_tables:
                    self.assertNotIn(table, executable_query)
                for value in expected:
                    self.assertIn(value, query)

    def test_demo_alert_and_response_are_explicitly_simulated(self):
        schema = json.loads(
            (ROOT / "alert-contract" / "normalized-alert.schema.json").read_text()
        )
        alert = json.loads((ROOT / "samples" / "demo-normalized-alert.json").read_text())
        response = json.loads(
            (ROOT / "samples" / "demo-simulated-response.json").read_text()
        )

        self.assertTrue(set(schema["required"]).issubset(alert))
        self.assertEqual(alert["severity"], "medium")
        self.assertIsNone(alert["resource_id"])
        self.assertTrue(alert["evidence"]["simulation"])
        self.assertEqual(
            set(alert["sentinel"].values()),
            {None},
        )
        self.assertTrue(response["simulation"])
        self.assertFalse(response["logic_app_invoked"])
        self.assertFalse(response["sentinel_alert_created"])
        self.assertFalse(response["sentinel_incident_created"])
        self.assertFalse(response["response"]["resource_changed"])
        self.assertFalse(response["response"]["account_disabled"])

    def test_each_query_has_an_inline_safe_kql_fixture(self):
        fixtures = {
            "waf-repeated-blocks-test.kql": (
                "blockedTransactions >= 5",
                "192.0.2.20",
            ),
            "waf-rate-limit-test.kql": ("blockedTransactions >= 10", "192.0.2.40"),
            "entra-repeated-failed-signins-test.kql": (
                "failures >= 10",
                "192.0.2.50",
            ),
            "entra-single-failure-test.kql": (
                "failureCount >= 1",
                "demo.user@example.invalid",
            ),
            "defender-alerts-test.kql": (
                "SampleSecurityAlerts",
                "simulated-alert-001",
            ),
            "azure-activity-repeated-failures-test.kql": (
                "sample-principal",
                "FailedOperationCount >= 5",
            ),
        }
        for name, expected in fixtures.items():
            with self.subTest(fixture=name):
                query = (ROOT / "tests" / name).read_text()
                self.assertIn("datatable(", query)
                for value in expected:
                    self.assertIn(value, query)
                self.assertIn("Expected result", query)


if __name__ == "__main__":
    unittest.main()
