// Handwritten, kept across regeneration (the codegen only writes its own files).
// Generated input structs only have `init(reader:)`, so app code outside this
// module can't build one. These add the plain initializers it needs.

extension ScanObjectInput {
    public init(scanObjectId: String, name: String, category: String, widthM: Double, heightM: Double, depthM: Double, photoUrl: String) {
        self.scanObjectId = scanObjectId
        self.name = name
        self.category = category
        self.widthM = widthM
        self.heightM = heightM
        self.depthM = depthM
        self.photoUrl = photoUrl
    }
}
