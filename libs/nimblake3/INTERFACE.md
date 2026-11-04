# nimblake3 INTERFACE

## Types
- `Blake3Hasher*`: value object wrapping the streaming hasher state
- `AssetInfo*`: object with `hash*, size*, mimeType*, createdAt*`
- `AssetStore*`: reference type wrapping a content-addressed store directory and SQLite database

## Procs
- `blake3Version*(): string`
- `initHasher*(): Blake3Hasher`
- `update*(h: var Blake3Hasher; data: openArray[byte])`
- `update*(h: var Blake3Hasher; text: string)`
- `finalizeHex*(h: Blake3Hasher): string`
- `blake3Hash*(data: openArray[byte]): string`
- `blake3Hash*(text: string): string`
- `blake3KeyedHash*(key: array[32, byte]; data: openArray[byte]): string`
- `openAssetStore*(dirPath: string): AssetStore`
- `close*(store: AssetStore)`
- `putBlob*(store: AssetStore; bytes: string; mimeType: string = "application/octet-stream"): string`
- `hasBlob*(store: AssetStore; hash: string): bool`
- `getBlob*(store: AssetStore; hash: string): string`
- `blobSize*(store: AssetStore; hash: string): int`
- `blobInfo*(store: AssetStore; hash: string): AssetInfo`
