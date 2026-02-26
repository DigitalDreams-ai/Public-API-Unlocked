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

        List<litify_pm__Firm__c> firmsWithParty = [
            SELECT Id, Party__c FROM litify_pm__Firm__c WHERE Party__c != null LIMIT 1
        ];
        Id partyId = firmsWithParty.isEmpty() ? null : firmsWithParty[0].Party__c;

        if (partyId == null) {
            List<Account> accounts = [SELECT Id FROM Account LIMIT 1];
            partyId = accounts.isEmpty() ? createPartyAccount() : accounts[0].Id;
        }

        litify_pm__Firm__c firm = new litify_pm__Firm__c(
            Name = 'Test Firm ' + String.valueOf(Crypto.getRandomInteger()),
            Party__c = partyId,
            litify_pm__ExternalId__c = Math.abs(Crypto.getRandomInteger())
        );
        insert firm;
        return firm;
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
