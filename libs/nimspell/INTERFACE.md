# nimspell INTERFACE
- `misspelled*(text: string): seq[(int, int)]` — misspelled words as UTF-8 byte ranges
- `suggestions*(word: string): seq[string]` — up to 8 corrections
- `addWord*(word: string)` — add to the user's dictionary
