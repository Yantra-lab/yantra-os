# nimfilament

3D for Yantra through [Filament](https://github.com/google/filament) (Apache-2.0): physically
based rendering, glTF 2.0 models with textures and animation, a sun with shadows.

Filament's Windows release (`third_party/filament`, v1.77.1) is built with MSVC and the Yantra
engine with MinGW, so the two meet at a small C API: `src/filament_shim.cpp`, built by
`build.bat` (Visual Studio Build Tools) into `build/yfilament.dll`. Scenes render offscreen into
BGRA pixels, which the engine draws like a video frame, so 3D works the same in a window, in a
film (frame-exact on the film's clock) and in a PDF.

Tests: `bash tests/run_tests.sh`, which renders the Khronos sample models (downloaded once into
`third_party/models`).
