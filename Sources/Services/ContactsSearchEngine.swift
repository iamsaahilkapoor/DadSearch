import Foundation
import Contacts

public final class ContactsSearchEngine: @unchecked Sendable {
    public static let shared = ContactsSearchEngine()

    private let contactStore = CNContactStore()

    private init() {}

    public func searchContacts(keyword: String, limit: Int = 10) -> [SearchItem] {
        guard !keyword.isEmpty else { return [] }

        // Check authorization status before querying to avoid blocking
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized else {
            return []
        }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor
        ]

        let predicate = CNContact.predicateForContacts(matchingName: keyword)
        do {
            let contacts = try contactStore.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            var results: [SearchItem] = []

            for contact in contacts.prefix(limit) {
                let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                let title = fullName.isEmpty ? (contact.organizationName.isEmpty ? "Contact" : contact.organizationName) : fullName

                var details: [String] = []
                if let phone = contact.phoneNumbers.first?.value.stringValue {
                    details.append(phone)
                }
                if let email = contact.emailAddresses.first?.value as String? {
                    details.append(email)
                }

                let subtitle = details.isEmpty ? "macOS Contacts" : details.joined(separator: " • ")

                let item = SearchItem(
                    id: "contact:" + contact.identifier,
                    title: title,
                    subtitle: subtitle,
                    fileURL: nil,
                    kind: .contact,
                    modificationDate: Date(),
                    addedDate: nil,
                    fileSize: nil,
                    authorOrSender: contact.organizationName.isEmpty ? nil : contact.organizationName,
                    isOutlookItem: false,
                    matchSnippet: details.first
                )
                results.append(item)
            }
            return results
        } catch {
            return []
        }
    }
}
