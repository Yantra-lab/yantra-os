# nimspell

The system spell checker for Yantra's text fields: Windows' `ISpellChecker` (Windows 8+, per-user
dictionary). On other systems it reports nothing. Used by render/native/engine.nim for inputs and
text areas with `spellcheck = true` (red underline, suggestions on right click).
