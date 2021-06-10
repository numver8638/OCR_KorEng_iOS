//
//  ViewController.swift
//  OCR_KorEng_iOS
//
//  Created by numver8638 on 2021/05/21.
//

import UIKit

/**
 * Dismiss delayed alert controller.
 * This prevents not disappearing alert due to race condition. 
 */
class DelayedAlertController : UIAlertController {
    private var didPresented = false

    private var flag: Bool?
    private var completion: (() -> Void)?
    
    override func viewDidAppear(_ animated: Bool) {
        didPresented = true
        
        if let flag = self.flag {
            // there's an pending dismiss
            
            super.dismiss(animated: flag, completion: completion)
        }
    }
    
    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        if didPresented {
            super.dismiss(animated: flag, completion: completion)
        }
        else {
            self.flag = flag
            self.completion = completion
        }
    }
}

class ViewController: UIViewController {
    private func alert(title: String, message: String) -> UIAlertController {
        let alertController = DelayedAlertController(title: title, message: message, preferredStyle: .alert)
        let action = UIAlertAction(title: "OK", style: .default)
        
        alertController.addAction(action)
        
        return alertController
    }

    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var stackView: UIStackView!
    @IBOutlet weak var label: UILabel!
    
    let picker = UIImagePickerController()
    
    var recognizer: Recognizer? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    
        picker.delegate = self
        
        Recognizer.newInstance { instance in
            self.recognizer = instance
        } onFailure: { error in
            let ctrl: UIAlertController
            
            switch error {
            case .invalidData:
                ctrl = self.alert(title: "Init Error", message: "Fail to load essential data.")
                
            case .failedToCreateInterpreter:
                ctrl = self.alert(title: "Init Error", message: "Fail to create interpreter.")
                
            case .internalError(let internalError):
                ctrl = self.alert(title: "Init Error", message: "Internal error: \(internalError)")
            }
            
            self.present(ctrl, animated: true)
        }
    }

    @IBAction func onClickCameraButton(_ sender: UIButton) {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            
            present(picker, animated: true)
            
        } else {
            let ctrl = alert(title: "Camera is inaccessible", message: "Cannot access to camera.")
            present(ctrl, animated: true)
        }
    }
    
    @IBAction func onClickImageButton(_ sender: UIButton) {
        picker.sourceType = .photoLibrary
        
        present(picker, animated: true)
    }
    
    private func run(withImage image: UIImage) {
        guard let recognizer = self.recognizer else {
            let ctrl = alert(title: "Recognition Failed", message: "Recognizer is not initalized. Please restart the app.")
            present(ctrl, animated: true)
            return
        }

        let progress = Progress()

        // Show activity indicator for user.
        let alert = DelayedAlertController(title: nil, message: "Processing...", preferredStyle: .alert)

        let activityIndicator = UIActivityIndicatorView(frame: CGRect(x: 10, y: 5, width: 50, height: 50))

        activityIndicator.hidesWhenStopped = false
        activityIndicator.style = .medium
        activityIndicator.startAnimating()

        alert.view.addSubview(activityIndicator)

        let action = UIAlertAction(title: "Cancel", style: .destructive) { _ in
            activityIndicator.stopAnimating()
            progress.cancel()

            self.textView.text = "User canceled operation."
        }
        alert.addAction(action)
        
        present(alert, animated: true)

        // Start recognition
        recognizer.recognize(input: image, progress: progress) { result in
            self.textView.text = result.text
            self.label.text = "Recognition Content: (\(result.confidence * 100.0)% accuracy)"

            // Dismiss activity indicator and present new alert
            activityIndicator.stopAnimating()
            progress.cancel()

            alert.dismiss(animated: true)
        } onFailure: { error in
            // Dismiss activity indicator and present new alert
            activityIndicator.stopAnimating()
            progress.cancel()

            alert.dismiss(animated: false) {
                let ctrl = self.alert(title: "Recognition Error", message: "\(error.localizedDescription)")

                self.present(ctrl, animated: true)
            }
        }
//        DispatchQueue.global(qos: .utility).async {
//            let output = OpenCVWrapper.processTest(image)
//
//            DispatchQueue.main.async { self.imageView.image = output }
//        }
    }
}

extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        var image: UIImage! = nil
        
        if let selectedImage = info[.originalImage] as? UIImage {
            image = selectedImage
            imageView.image = selectedImage
        }
        
        picker.dismiss(animated: true)
        
        if image != nil {
            run(withImage: image!)
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
