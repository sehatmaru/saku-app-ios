#!/usr/bin/env python3
"""Merges Docs/en_part*.json (Indonesian key -> English) into App/Resources/Localizable.xcstrings."""
import json, glob
en = {}
for f in sorted(glob.glob('Docs/en_part*.json')):
    en.update(json.load(open(f)))
strings = {k: {"localizations": {"en": {"stringUnit": {"state": "translated", "value": v}}}} for k, v in sorted(en.items())}
# Plural forms for keys shown through Text("...\(n)...") (one / other).
PLURAL = {"%lld akun": ("%lld account", "%lld accounts"),
          "Total saldo · %lld akun": ("Total balance · %lld account", "Total balance · %lld accounts")}
for k, (one, other) in PLURAL.items():
    unit = lambda v: {"stringUnit": {"state": "translated", "value": v}}
    strings[k] = {"localizations": {"en": {"variations": {"plural": {"one": unit(one), "other": unit(other)}}}}}
json.dump({"sourceLanguage": "id", "strings": strings, "version": "1.0"},
          open('App/Resources/Localizable.xcstrings', 'w'), ensure_ascii=False, indent=2)
print(len(strings), "keys")
