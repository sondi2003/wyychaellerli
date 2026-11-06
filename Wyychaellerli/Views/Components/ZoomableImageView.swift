import AVFoundation
import SwiftUI
import UIKit

/// Ein Bild zum Zoomen und Verschieben – mit Fingerspreizen und Doppeltipp.
///
/// UIKit statt SwiftUI-Gesten: `UIScrollView` bringt Trägheit, Anschlag an den Rändern
/// und das Zentrieren gleich mit. In SwiftUI müsste man das alles nachbauen, und es
/// fühlt sich nie ganz nach iOS an.
struct ZoomableImageView: UIViewRepresentable {

    let image: UIImage

    func makeUIView(context: Context) -> ZoomScrollView {
        let scrollView = ZoomScrollView()
        scrollView.delegate = context.coordinator
        scrollView.imageView.image = image
        scrollView.showsSignature = CatalogPhotoFade.isCatalogBottle(image)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: ZoomScrollView, context: Context) {
        if scrollView.imageView.image !== image {
            scrollView.imageView.image = image
            scrollView.zoomScale = 1
            scrollView.showsSignature = CatalogPhotoFade.isCatalogBottle(image)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ZoomScrollView)?.centerImage()
        }

        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? ZoomScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                // Auf den angetippten Punkt zoomen, nicht auf die Mitte.
                let point = recognizer.location(in: scrollView.imageView)
                let scale: CGFloat = 3
                let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
                let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                  width: size.width, height: size.height)
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}

/// Die Scroll-Ansicht misst sich selbst aus. Beim ersten `updateUIView` ist die Grösse
/// noch 0×0 – wer das Bild dort einpasst, bekommt ein schwarzes Vollbild. Erst
/// `layoutSubviews` kennt die echten Masse.
final class ZoomScrollView: UIScrollView {

    let imageView = UIImageView()
    private var laidOutSize: CGSize = .zero

    /// Der Name der App unten auf einem Katalogfoto (wie auf der Detailseite). Er liegt **im**
    /// gezoomten Bild und wächst beim Zoomen mit – wie ein Aufdruck.
    private let signatureLabel = UILabel()
    var showsSignature = false {
        didSet {
            signatureLabel.isHidden = !showsSignature
            setNeedsLayout()
            layoutSignature()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        minimumZoomScale = 1
        maximumZoomScale = 6
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bouncesZoom = true
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        signatureLabel.text = "Wyychällerli"
        signatureLabel.textColor = UIColor(Brand.accent)
        signatureLabel.isHidden = true
        imageView.addSubview(signatureLabel)
    }

    required init?(coder: NSCoder) { fatalError("nicht aus einem Storyboard") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize, bounds.width > 0, bounds.height > 0 else { return }
        laidOutSize = bounds.size
        zoomScale = 1
        imageView.frame = CGRect(origin: .zero, size: bounds.size)
        contentSize = bounds.size
        centerImage()
        layoutSignature()
    }

    /// Setzt den Namen auf rund 97 % der Höhe des **angezeigten Bildes** (nicht des Fensters:
    /// Die Flasche ist schmaler als der Bildschirm).
    private func layoutSignature() {
        guard showsSignature, let image = imageView.image, image.size.height > 0,
              imageView.bounds.width > 0 else { return }
        let shown = AVMakeRect(aspectRatio: image.size, insideRect: imageView.bounds)
        signatureLabel.font = .systemFont(ofSize: max(11, shown.height * 0.022), weight: .medium)
        signatureLabel.sizeToFit()
        signatureLabel.center = CGPoint(x: shown.midX, y: shown.minY + shown.height * 0.965)
    }

    /// Hält das Bild in der Mitte, solange es kleiner als der Bildschirm ist.
    func centerImage() {
        let content = imageView.frame.size
        let dx = max(0, (bounds.width - content.width) / 2)
        let dy = max(0, (bounds.height - content.height) / 2)
        contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
    }
}

/// Vollbild für die Etikettfotos: blätterbar zwischen den Seiten, jede zoombar.
struct LabelZoomView: View {

    let pages: [LabelPage]
    @State var selection: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    ZoomableImageView(image: page.image)
                        .tag(index)
                        .accessibilityLabel(page.title)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: pages.count > 1 ? .always : .never))
            // Folgt dem Farbschema der App (Einstellungen → Darstellung): hell im hellen Design,
            // schwarz im dunklen. Früher fest schwarz – eine dunkle Flasche vor durchsichtigem
            // Grund ging darin unter, und im hellen Design sprang man in ein schwarzes Fenster.
            .background(Color(.systemBackground))
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(pages.indices.contains(selection) ? pages[selection].title : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
