/**
 * Minimal test data factory for Unbounce API tests.
 * Creates Firm and CaseType required for intake creation.
 */
@IsTest
public class UnbounceTestDataFactory {

    public static litify_pm__Firm__c createFirm() {
        List<litify_pm__Firm__c> existing = [SELECT Id FROM litify_pm__Firm__c LIMIT 1];
        if (!existing.isEmpty()) {
            return existing[0];
        }

        Id partyId = findExistingFirmPartyId();

        if (partyId == null) {
            List<Account> accounts = [SELECT Id FROM Account LIMIT 1];
            partyId = accounts.isEmpty() ? createPartyAccount() : accounts[0].Id;
        }

        litify_pm__Firm__c firm = new litify_pm__Firm__c(
            Name = 'Test Firm ' + String.valueOf(Crypto.getRandomInteger()),
            litify_pm__ExternalId__c = Math.abs(Crypto.getRandomInteger())
        );
        setOptionalFirmField(firm, 'Party__c', partyId);
        insert firm;
        return firm;
    }

    private static Id findExistingFirmPartyId() {
        Map<String, Schema.SObjectField> firmFields =
            litify_pm__Firm__c.SObjectType.getDescribe().fields.getMap();
        if (!firmFields.containsKey('Party__c')) {
            return null;
        }

        List<SObject> firmsWithParty = Database.query(
            'SELECT Id, Party__c FROM litify_pm__Firm__c WHERE Party__c != null LIMIT 1'
        );
        return firmsWithParty.isEmpty() ? null : (Id) firmsWithParty[0].get('Party__c');
    }

    private static void setOptionalFirmField(litify_pm__Firm__c firm, String fieldName, Object value) {
        if (firm == null || String.isBlank(fieldName) || value == null) {
            return;
        }
        Map<String, Schema.SObjectField> firmFields =
            litify_pm__Firm__c.SObjectType.getDescribe().fields.getMap();
        if (!firmFields.containsKey(fieldName)) {
            return;
        }
        firm.put(fieldName, value);
    }

    private static Id createPartyAccount() {
        Account a = new Account(Name = 'Test Party');
        try {
            a.put('litify_pm__Last_Name__c', 'Party');
        } catch (SObjectException e) {
            for (Schema.SObjectField f : Account.SObjectType.getDescribe().fields.getMap().values()) {
                Schema.DescribeFieldResult df = f.getDescribe();
                if (df.getName().toLowerCase().contains('last') && df.getType() == Schema.DisplayType.String && df.isCreateable()) {
                    a.put(df.getName(), 'Party');
                    break;
                }
            }
        }
        insert a;
        return a.Id;
    }

    public static litify_pm__Case_Type__c createCaseType(String name) {
        List<litify_pm__Case_Type__c> existing = [
            SELECT Id FROM litify_pm__Case_Type__c WHERE Name = :name LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }
        litify_pm__Case_Type__c ct = new litify_pm__Case_Type__c(Name = name);
        insert ct;
        return ct;
    }
}
