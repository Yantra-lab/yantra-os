# Galerie Nocturne: artwork and scan credits

These are the six collection scans packaged inside the installed gallery at `apps/gallery/art/`.
The JPEG bytes are preserved from `assets/gallery3d/art/`; each is stored upright and cropped to
4:5 (1024×1280). The engine resolves the `Image` node's `art/<file>.jpg` source from the installed
`apps/gallery/` package, not from a temporary staging directory. Image nodes use `fit = 0`
(contain), so rendering preserves the packaged image's aspect ratio and adds no further crop.
The other two works are original computational plates drawn live by `apps/gallery/app.nim`.

| File | Title | Artist | Year | Source and rights |
|---|---|---|---|---|
| ravi-varma.jpg | There Comes Papa | Raja Ravi Varma | 1893 | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Raja_Ravi_Varma,_There_Comes_Papa_(1893).jpg) · public domain (artist died 1906) |
| hokusai.jpg | Under the Wave off Kanagawa (The Great Wave) | Katsushika Hokusai | c. 1830–1832 | [The Met, 29.100.468](https://commons.wikimedia.org/wiki/File:The_Great_Wave_off_Kanagawa.jpg) · CC0 / public domain |
| vermeer.jpg | The Milkmaid | Johannes Vermeer | c. 1660 | [Rijksmuseum, SK-A-2344](https://commons.wikimedia.org/wiki/File:Johannes_Vermeer_-_Het_melkmeisje_-_Google_Art_Project.jpg) · public domain |
| sher-gil.jpg | Three Girls | Amrita Sher-Gil | 1935 | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Group_of_Three_Girls_1935.jpg) · public domain in India since 2002 (artist died 1941); US status not checked |
| van-gogh.jpg | Wheat Field with Cypresses | Vincent van Gogh | 1889 | [The Met, 39.73](https://commons.wikimedia.org/wiki/File:Wheat_Field_with_Cypresses_MET_DT1567.jpg) · CC0 / public domain |
| monet.jpg | Water Lilies | Claude Monet | 1906 | [Art Institute of Chicago, 1933.1157](https://commons.wikimedia.org/wiki/File:Claude_Monet_-_Water_Lilies_-_1933.1157_-_Art_Institute_of_Chicago.jpg) · CC0 / public domain |

Source images fetched and cropped by the Flash lane (bridge task P2), 2026-10-05; renamed and
stored upright by Claude. Moved unchanged into the installed app package by gallery-craft; the
duplicate external gallery asset folder was removed.
