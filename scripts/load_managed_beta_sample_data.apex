Map<String, Schema.RecordTypeInfo> accountRecordTypesByDeveloperName =
    Account.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();

Account sampleAccount = new Account(
    Name = 'Sample Acme',
    Phone = '5551238765',
    Type = 'Prospect',
    Industry = 'Biotechnology'
);

if (accountRecordTypesByDeveloperName.containsKey('Business')) {
    Schema.RecordTypeInfo businessRecordType = accountRecordTypesByDeveloperName.get('Business');
    if (businessRecordType != null && businessRecordType.isAvailable()) {
        sampleAccount.put('RecordTypeId', businessRecordType.getRecordTypeId());
    }
}

insert sampleAccount;
