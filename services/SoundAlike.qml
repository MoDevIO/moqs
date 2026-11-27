pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Everyday German words that sound like the start of a Latin word (ambulare: Ampel, Ambulanz;
// vitium: Witz, Video), as keywords for Mnemonic's scenes: a language model can't hear what
// a word sounds like, so the words are found here and the model only builds the picture.
//
// The words are german-words.txt next to shell.qml (common German words, most frequent
// first; made by nix/german-words.py, in the package or with `nix build .#german-words -o
// german-words.txt`). Without it there are none.
//
// Both sides become a rough sound spelling: Latin read as at school (v as w, c as k, or z
// before e and i), German with sch, ch, ck, tz, ie and the like as they're said, voiced
// and unvoiced consonants alike (d as t) except at the start, where they're heard (perdere
// isn't Bert), no doubled letters. A word fits when its sound spelling starts like the Latin
// one's, at least through the first syllable. Nouns come first, since they make pictures;
// abbreviations (AfD) and very common small words (wieder, indem, obwohl) are left out.
Singleton {
    id: root

    // [{ word, sound, first }], most frequent first; `first` the first letter before voiced
    // and unvoiced were merged.
    property var words: []
    readonly property bool available: words.length > 0

    // Up to `n` words for the Latin `latin`, the best fits first, then the more common;
    // those in `skip` (lower case) left out.
    function find(latin: string, n: int, skip: var): var {
        const spelt = latinSpelling(latin.trim().split(/[ ,]/)[0]);
        const k = merge(spelt);
        if (!k)
            return [];
        // Through the first syllable: its consonants, vowels and the next consonant.
        const syllable = k.match(/^[^aeiouöü]*[aeiouöü]+[^aeiouöü]?/)?.[0].length ?? 3;
        const need = Math.min(k.length, Math.max(3, syllable));
        let fits = [];
        for (let i = 0; i < words.length; i++) {
            const w = words[i];
            // A small, very common word ("wieder") makes no picture; nor does an abbreviation.
            if (w.first !== spelt[0] || (i < 1500 && w.word[0] === w.word[0].toLowerCase()) || /[A-ZÄÖÜ].*[A-ZÄÖÜ]/.test(w.word))
                continue;
            const s = w.sound;
            let same = 0;
            while (same < s.length && same < k.length && s[same] === k[same])
                same++;
            if (same >= need - 1)
                fits.push({ word: w.word, same, rank: i, noun: w.word[0] !== w.word[0].toLowerCase() });
        }
        // One sound short only when there are few that fit fully.
        if (fits.filter(f => f.same >= need).length >= 3)
            fits = fits.filter(f => f.same >= need);
        fits.sort((a, b) => b.same - a.same || b.noun - a.noun || a.rank - b.rank);
        const out = [];
        for (const f of fits) {
            const low = f.word.toLowerCase();
            if (!skip.includes(low) && !out.some(w => w.toLowerCase() === low))
                out.push(f.word);
            if (out.length >= n)
                break;
        }
        return out;
    }

    // The sound spelling of a Latin word, read as at school, before merge().
    function latinSpelling(w: string): string {
        w = String(w).normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
        w = w.replace(/c(?=[eiy]|ae|oe)/g, "z").replace(/qu/g, "kw").replace(/ae/g, "e").replace(/oe/g, "ö").replace(/ph/g, "f").replace(/th/g, "t").replace(/v/g, "w").replace(/c/g, "k").replace(/y/g, "i");
        return spelling(w);
    }

    // The sound spelling of a German word, before merge().
    function spelling(w: string): string {
        w = String(w).toLowerCase().replace(/ä/g, "e").replace(/ß/g, "s");
        for (const [a, b] of [["sch", "S"], ["ch", "k"], ["ck", "k"], ["tz", "z"], ["ph", "f"], ["th", "t"], ["qu", "kw"], ["ie", "i"], ["ei", "ai"], ["ey", "ai"], ["ay", "ai"], ["eu", "oi"], ["äu", "oi"], ["x", "ks"], ["v", "w"], ["y", "i"], ["c", "k"]])
            w = w.split(a).join(b);
        // A lengthening h ("Bahn") isn't heard.
        return w.replace(/([aeiouöü])h(?![aeiouöü])/g, "$1").replace(/z/g, "ts");
    }

    // Voiced and unvoiced consonants alike, no doubled letters.
    function merge(w: string): string {
        return w.replace(/d/g, "t").replace(/b/g, "p").replace(/g/g, "k").replace(/(.)\1+/g, "$1");
    }

    FileView {
        path: Quickshell.shellPath("german-words.txt")
        printErrors: false
        onLoaded: root.words = text().split("\n").filter(w => w).map(word => {
            const spelt = root.spelling(word);
            return {
                word,
                sound: root.merge(spelt),
                first: spelt[0]
            };
        })
    }
}
