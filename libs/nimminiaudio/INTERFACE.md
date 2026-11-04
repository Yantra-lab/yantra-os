# nimminiaudio INTERFACE

## Types
- `AudioFormat`: `formatUnknown`, `formatU8`, `formatS16`, `formatS24`, `formatS32`, `formatF32`
- `WaveformType`: `waveSine`, `waveSquare`, `waveTriangle`, `waveSawtooth`
- `EncodingFormat`: `encodingUnknown`, `encodingWav`, `encodingFlac`, `encodingMp3`, `encodingVorbis`
- `Waveform`, `Encoder`, `Decoder`, `SpatializerListener`, `Spatializer`

## Procs
- `newWaveform*(format: AudioFormat; channels, sampleRate: int; waveType: WaveformType; amplitude, frequency: float64): Waveform`
- `free*(obj: Waveform | Encoder | Decoder | SpatializerListener | Spatializer)`
- `readPcmFrames*(wave: Waveform | Decoder; framesOut: pointer; frameCount: int): int`
- `setAmplitude*(wave: Waveform; amplitude: float64)`
- `setFrequency*(wave: Waveform; frequency: float64)`
- `setType*(wave: Waveform; waveType: WaveformType)`
- `newEncoder*(filePath: string; encoding: EncodingFormat; format: AudioFormat; channels, sampleRate: int): Encoder`
- `writePcmFrames*(enc: Encoder; framesIn: pointer; frameCount: int): int`
- `newDecoder*(filePath: string): Decoder`
- `lengthInPcmFrames*(dec: Decoder): int`
- `seekToPcmFrame*(dec: Decoder; frameIndex: int)`
- `mixPcmFrames*(dst: var openArray[float32]; src: openArray[float32]; frameCount: int; channels = 1; volume = 1.0f32)`
- `newSpatializerListener*(channelsOut: int): SpatializerListener`
- `setPosition*(obj: SpatializerListener | Spatializer; x, y, z: float32)`
- `setDirection*(listener: SpatializerListener; x, y, z: float32)`
- `newSpatializer*(channelsIn, channelsOut: int): Spatializer`
- `processPcmFrames*(spat: Spatializer; listener: SpatializerListener; framesOut, framesIn: pointer; frameCount: int)`
