//
// DepthAnythingV2SmallF16.swift
//
// This file was automatically generated and should not be edited.
//

import CoreML


/// Model Prediction Input Type
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
class DepthAnythingV2SmallF16Input : MLFeatureProvider {

    /// Input image whose depth will be estimated. The shorter dimension should be 518 pixels and the larger dimension should be a multiple of 14. as color (kCVPixelFormatType_32BGRA) image buffer, 518 pixels wide by 392 pixels high
    var image: CVPixelBuffer

    var featureNames: Set<String> { ["image"] }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        if featureName == "image" {
            return MLFeatureValue(pixelBuffer: image)
        }
        return nil
    }

    init(image: CVPixelBuffer) {
        self.image = image
    }

    convenience init(imageWith image: CGImage) throws {
        self.init(image: try MLFeatureValue(cgImage: image, pixelsWide: 518, pixelsHigh: 392, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!)
    }

    convenience init(imageAt image: URL) throws {
        self.init(image: try MLFeatureValue(imageAt: image, pixelsWide: 518, pixelsHigh: 392, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!)
    }

    func setImage(with image: CGImage) throws  {
        self.image = try MLFeatureValue(cgImage: image, pixelsWide: 518, pixelsHigh: 392, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!
    }

    func setImage(with image: URL) throws  {
        self.image = try MLFeatureValue(imageAt: image, pixelsWide: 518, pixelsHigh: 392, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!
    }

}


/// Model Prediction Output Type
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
class DepthAnythingV2SmallF16Output : MLFeatureProvider {

    /// Source provided by CoreML
    private let provider : MLFeatureProvider

    /// Estimated depth map, as a grayscale output image. as grayscale (kCVPixelFormatType_OneComponent16Half) image buffer, 518 pixels wide by 392 pixels high
    var depth: CVPixelBuffer {
        provider.featureValue(for: "depth")!.imageBufferValue!
    }

    var featureNames: Set<String> {
        provider.featureNames
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        provider.featureValue(for: featureName)
    }

    init(depth: CVPixelBuffer) {
        self.provider = try! MLDictionaryFeatureProvider(dictionary: ["depth" : MLFeatureValue(pixelBuffer: depth)])
    }

    init(features: MLFeatureProvider) {
        self.provider = features
    }
}


/// Class for model loading and prediction
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
class DepthAnythingV2SmallF16 {
    let model: MLModel

    /// URL of model assuming it was installed in the same bundle as this class
    class var urlOfModelInThisBundle : URL {
        let bundle = Bundle(for: self)
        return bundle.url(forResource: "DepthAnythingV2SmallF16", withExtension:"mlmodelc")!
    }

    /**
        Construct DepthAnythingV2SmallF16 instance with an existing MLModel object.

        Usually the application does not use this initializer unless it makes a subclass of DepthAnythingV2SmallF16.
        Such application may want to use `MLModel(contentsOfURL:configuration:)` and `DepthAnythingV2SmallF16.urlOfModelInThisBundle` to create a MLModel object to pass-in.

        - parameters:
          - model: MLModel object
    */
    init(model: MLModel) {
        self.model = model
    }

    /**
        Construct a model with configuration

        - parameters:
           - configuration: the desired model configuration

        - throws: an NSError object that describes the problem
    */
    convenience init(configuration: MLModelConfiguration = MLModelConfiguration()) throws {
        try self.init(contentsOf: type(of:self).urlOfModelInThisBundle, configuration: configuration)
    }

    /**
        Construct DepthAnythingV2SmallF16 instance with explicit path to mlmodelc file
        - parameters:
           - modelURL: the file url of the model

        - throws: an NSError object that describes the problem
    */
    convenience init(contentsOf modelURL: URL) throws {
        try self.init(model: MLModel(contentsOf: modelURL))
    }

    /**
        Construct a model with URL of the .mlmodelc directory and configuration

        - parameters:
           - modelURL: the file url of the model
           - configuration: the desired model configuration

        - throws: an NSError object that describes the problem
    */
    convenience init(contentsOf modelURL: URL, configuration: MLModelConfiguration) throws {
        try self.init(model: MLModel(contentsOf: modelURL, configuration: configuration))
    }

    /**
        Construct DepthAnythingV2SmallF16 instance asynchronously with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - configuration: the desired model configuration
          - handler: the completion handler to be called when the model loading completes successfully or unsuccessfully
    */
    class func load(configuration: MLModelConfiguration = MLModelConfiguration(), completionHandler handler: @escaping (Swift.Result<DepthAnythingV2SmallF16, Error>) -> Void) {
        load(contentsOf: self.urlOfModelInThisBundle, configuration: configuration, completionHandler: handler)
    }

    /**
        Construct DepthAnythingV2SmallF16 instance asynchronously with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - configuration: the desired model configuration
    */
    class func load(configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> DepthAnythingV2SmallF16 {
        try await load(contentsOf: self.urlOfModelInThisBundle, configuration: configuration)
    }

    /**
        Construct DepthAnythingV2SmallF16 instance asynchronously with URL of the .mlmodelc directory with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - modelURL: the URL to the model
          - configuration: the desired model configuration
          - handler: the completion handler to be called when the model loading completes successfully or unsuccessfully
    */
    class func load(contentsOf modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration(), completionHandler handler: @escaping (Swift.Result<DepthAnythingV2SmallF16, Error>) -> Void) {
        MLModel.load(contentsOf: modelURL, configuration: configuration) { result in
            switch result {
            case .failure(let error):
                handler(.failure(error))
            case .success(let model):
                handler(.success(DepthAnythingV2SmallF16(model: model)))
            }
        }
    }

    /**
        Construct DepthAnythingV2SmallF16 instance asynchronously with URL of the .mlmodelc directory with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - modelURL: the URL to the model
          - configuration: the desired model configuration
    */
    class func load(contentsOf modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> DepthAnythingV2SmallF16 {
        let model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)
        return DepthAnythingV2SmallF16(model: model)
    }

    /**
        Make a prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as DepthAnythingV2SmallF16Input

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as DepthAnythingV2SmallF16Output
    */
    func prediction(input: DepthAnythingV2SmallF16Input) throws -> DepthAnythingV2SmallF16Output {
        try prediction(input: input, options: MLPredictionOptions())
    }

    /**
        Make a prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as DepthAnythingV2SmallF16Input
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as DepthAnythingV2SmallF16Output
    */
    func prediction(input: DepthAnythingV2SmallF16Input, options: MLPredictionOptions) throws -> DepthAnythingV2SmallF16Output {
        let outFeatures = try model.prediction(from: input, options: options)
        return DepthAnythingV2SmallF16Output(features: outFeatures)
    }

    /**
        Make an asynchronous prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as DepthAnythingV2SmallF16Input
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as DepthAnythingV2SmallF16Output
    */
    func prediction(input: DepthAnythingV2SmallF16Input, options: MLPredictionOptions = MLPredictionOptions()) async throws -> DepthAnythingV2SmallF16Output {
        let outFeatures = try await model.prediction(from: input, options: options)
        return DepthAnythingV2SmallF16Output(features: outFeatures)
    }

    /**
        Make a prediction using the convenience interface

        It uses the default function if the model has multiple functions.

        - parameters:
            - image: Input image whose depth will be estimated. The shorter dimension should be 518 pixels and the larger dimension should be a multiple of 14. as color (kCVPixelFormatType_32BGRA) image buffer, 518 pixels wide by 392 pixels high

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as DepthAnythingV2SmallF16Output
    */
    func prediction(image: CVPixelBuffer) throws -> DepthAnythingV2SmallF16Output {
        let input_ = DepthAnythingV2SmallF16Input(image: image)
        return try prediction(input: input_)
    }

    /**
        Make a batch prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - inputs: the inputs to the prediction as [DepthAnythingV2SmallF16Input]
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as [DepthAnythingV2SmallF16Output]
    */
    func predictions(inputs: [DepthAnythingV2SmallF16Input], options: MLPredictionOptions = MLPredictionOptions()) throws -> [DepthAnythingV2SmallF16Output] {
        let batchIn = MLArrayBatchProvider(array: inputs)
        let batchOut = try model.predictions(from: batchIn, options: options)
        var results : [DepthAnythingV2SmallF16Output] = []
        results.reserveCapacity(inputs.count)
        for i in 0..<batchOut.count {
            let outProvider = batchOut.features(at: i)
            let result =  DepthAnythingV2SmallF16Output(features: outProvider)
            results.append(result)
        }
        return results
    }
}
