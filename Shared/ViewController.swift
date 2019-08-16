
import MetalKit

#if targetEnvironment(simulator)
    #warning("Cannot build a Metal target for simulator")
#endif

class ViewController: NUViewController {
    var mtkView: MTKView {
        return view as! MTKView
    }

    var renderer: Renderer!

    var lastPanLocation = CGPoint()

    override func viewDidLoad() {
        super.viewDidLoad()

        addGestureRecognizers()

        renderer = Renderer(view: mtkView)
    }
}

// MARK: - gesture recognizers

extension ViewController: NUGestureRecognizerDelegate {
    fileprivate func addGestureRecognizers() {
        let tapClickRecognizer = NUTapClickGestureRecognizer(target: self, action: #selector(handleTapClick(recognizer:)))
        let panRecognizer = NUPanGestureRecognizer(target: self, action: #selector(handlePan(recognizer:)))

        tapClickRecognizer.delegate = self
        panRecognizer.delegate = self

        view.addGestureRecognizer(tapClickRecognizer)
        view.addGestureRecognizer(panRecognizer)
    }

    func gestureRecognizer(_: NUGestureRecognizer, shouldRecognizeSimultaneouslyWith _: NUGestureRecognizer) -> Bool {
        printClassAndFunc()
        return true
    }

    @objc func handleTapClick(recognizer: NUTapClickGestureRecognizer) {
        let location = recognizer.locationFromTop(in: view)
        printClassAndFunc(info: "\(location)")

        renderer.handleTapClickAt(view: mtkView, location: location)
    }

    @objc func handlePan(recognizer: NUPanGestureRecognizer) {
        let location = recognizer.locationFromTop(in: view)
        printClassAndFunc(info: "\(location)  \(recognizer.state.rawValue)")
        let panSensitivity: Float = 5.0
        switch recognizer.state {
        case .began:
            lastPanLocation = location
        case .changed:
            _ = Float((lastPanLocation.x - location.x) / view.bounds.width) * panSensitivity
            _ = Float((lastPanLocation.y - location.y) / view.bounds.height) * panSensitivity
            // printClassAndFunc(info: "\(xDelta) \(yDelta) ")
            lastPanLocation = location
        case .ended:
            break
        default:
            break
        }

        // TODO: use pan to rotate sphere cluster
    }
}
