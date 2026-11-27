# Writes common German words, most frequent first, one a line, for the vocabulary's
# sound-alike keywords (services/SoundAlike.qml): wordfreq's frequencies, spelt as the
# hunspell dictionary has them, so nouns keep their capital.
#
#   python3 german-words.py de_DE.dic out.txt
#
# Lower-case dictionary entries flagged h, o or z are only parts of compounds ("witz" in
# "aberwitzig", "ampel" in "Fußgängerampel"), capitalised ones flagged h only sentence starts
# ("Nicht").
import sys

import wordfreq

forms = {}
for line in open(sys.argv[1], encoding="latin-1"):
    word, _, flags = line.strip().partition("/")
    if word.isalpha():
        forms.setdefault(word.lower(), []).append((word, flags))


def spelling(word):
    found = forms.get(word)
    if not found:
        return None
    if any(w == word and not set("hoz") & set(f) for w, f in found):
        return word
    caps = [w for w, f in found if w[0].isupper() and "h" not in f]
    return caps[0] if caps else word


out = []
for word in wordfreq.top_n_list("de", 80000):
    s = spelling(word) if len(word) >= 3 and word.isalpha() else None
    if s:
        out.append(s)
with open(sys.argv[2], "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
