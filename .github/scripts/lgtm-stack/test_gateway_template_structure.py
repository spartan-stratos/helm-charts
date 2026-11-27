"""Check gateway definitions against Helm's chart-wide global template namespace."""
from collections import Counter
from pathlib import Path
import re
import unittest

REPO = Path(__file__).resolve().parents[3]
TEMPLATES = REPO / "charts/lgtm-stack/templates"
COMMENT = re.compile(r"{{-?\s*/\*.*?\*/\s*-?}}", re.DOTALL)
# Quoted action strings can themselves contain braces or apparent define actions.
ACTION = re.compile(r'{{-?\s*((?:"(?:\\.|[^"\\])*"|`[^`]*`|[^"}]|}(?!}))*?)\s*-?}}', re.DOTALL)
DEFINE = re.compile(r'define\s+(?:"([^"\\]+)"|`([^`]+)`)\s*-?')


def definitions(text):
    names = []
    for action in ACTION.finditer(COMMENT.sub("", text)):
        match = DEFINE.fullmatch(action.group(1).strip())
        if action.group(1).strip().startswith("define ") and not match:
            raise AssertionError("Definition requires an auditable literal name")
        if match:
            names.append(match.group(1) or match.group(2))
    return names


def validate(sources):
    parsed = {path: definitions(text) for path, text in sources.items()}
    gateway = [name for path, names in parsed.items()
               if Path(path).name.startswith("_gateway") and Path(path).suffix == ".tpl" for name in names]
    if not gateway:
        raise AssertionError("No gateway definitions inspected")
    if any(not name.startswith("lgtm-stack.") for name in gateway):
        raise AssertionError("Gateway definition requires chart namespace")
    counts = Counter(name for names in parsed.values() for name in names)
    if any(counts[name] != 1 for name in gateway):
        raise AssertionError("Gateway definition collides in parent chart")


class GatewayStructureTest(unittest.TestCase):
    def sources(self):
        return {str(path.relative_to(TEMPLATES)): path.read_text()
                for path in TEMPLATES.rglob("*") if path.is_file()}

    def test_actual_parent_chart_namespace(self):
        validate(self.sources())

    def test_duplicate_gateway_definition_in_other_parent_template_is_rejected(self):
        sources = self.sources()
        name = next(name for path, text in sources.items() if Path(path).name.startswith("_gateway")
                    for name in definitions(text))
        sources["collision.yaml"] = '{{ define "' + name + '" }}counterfactual{{ end }}'
        with self.assertRaisesRegex(AssertionError, "collides"):
            validate(sources)

    def test_unprefixed_new_definition_is_rejected(self):
        sources = self.sources()
        sources["_gateway-counterfactual.tpl"] = '{{ define "receiver" }}counterfactual{{ end }}'
        with self.assertRaisesRegex(AssertionError, "namespace"):
            validate(sources)

    def test_comments_and_quoted_examples_are_not_definitions(self):
        text = ('{{/* {{ define "comment-example" }} */}}'
                '{{- /* {{ define "trimmed-comment" }} */ -}}'
                '{{ printf "{{ define \\"quoted-example\\" }}" }}'
                '{{- define `lgtm-stack.example` -}}actual{{- end -}}')
        self.assertEqual(definitions(text), ["lgtm-stack.example"])

    def test_existing_unrelated_names_are_not_renamed(self):
        validate({"_gateway.tpl": '{{ define "lgtm-stack.gateway" }}{{ end }}',
                  "_legacy.tpl": '{{ define "legacy" }}{{ end }}'})


if __name__ == "__main__":
    unittest.main()
