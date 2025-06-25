public with sharing class OpportunityTriggerHandler extends TriggerHandler {

  
    protected override void beforeInsert() {
        // Set default Type for new Opportunities
        //Opportunity opp = Trigger.new[0];
        for (Opportunity opp : (List<Opportunity>) Trigger.new) {
            if (opp.Type == null) {
                opp.Type = 'New Customer';
            }
        }  
    }

    protected override void beforeUpdate() {
        //validate that the amount is greater than 5000
        for (Opportunity opp : (List<Opportunity>) Trigger.new) {
            if(opp.Amount < 5000) {
                opp.addError('Opportunity amount must be greater than 5000');
            }
        }
        // Append Stage changes in Opportunity Description
        for (Opportunity opp : (List<Opportunity>) Trigger.new) {
            //for (Opportunity oldOpp : Trigger.old){
            Opportunity oldOpp = (Opportunity) Trigger.oldMap.get(opp.Id);
            if (opp.StageName != null && opp.StageName != oldOpp.StageName) {
                String oldDescription = oldOpp.Description == null ? '' : oldOpp.Description;
                opp.Description = oldDescription + '\n Stage Change:' + opp.StageName + ':' + DateTime.now().format();
            }
                //}                
        }   
        //When an opportunity is updated set the primary contact on the opportunity to the contact with the title of 'CEO'.
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity opp : (List<Opportunity>) Trigger.new) {
            accountIds.add(opp.AccountId);
        }
        
        Map<Id, Contact> contacts = new Map<Id, Contact>([SELECT Id, FirstName, AccountId FROM Contact WHERE AccountId IN :accountIds AND Title = 'CEO' ORDER BY FirstName ASC]);
        Map<Id, Contact> accountIdToContact = new Map<Id, Contact>();

        for (Contact cont : contacts.values()) {
            if (!accountIdToContact.containsKey(cont.AccountId)) {
                accountIdToContact.put(cont.AccountId, cont);
            }
        }

        for (Opportunity opp : (List<Opportunity>) Trigger.new) {
            if(opp.Primary_Contact__c == null){
                if (accountIdToContact.containsKey(opp.AccountId)){
                    opp.Primary_Contact__c = accountIdToContact.get(opp.AccountId).Id;
                }
            }
        }

    }

    protected override void beforeDelete() {
        // Prevent deletion of closed Opportunities
        for (Opportunity oldOpp : (List<Opportunity>) Trigger.old) {
            if (oldOpp.IsClosed) {
                oldOpp.addError('Cannot delete closed opportunity');
            }
        }

        //prevent the deletion of a closed won opportunity if the account industry is 'Banking'.
        Map<Id, Account> accounts = new Map<Id, Account>([SELECT Id, Industry FROM Account WHERE Id IN (SELECT AccountId FROM Opportunity WHERE Id IN :Trigger.old)]);
        for (Opportunity opp : (List<Opportunity>) Trigger.old) {
            if (opp.StageName == 'Closed Won') {
                if (accounts.get(opp.AccountId).Industry == 'Banking') {
                    opp.addError('Cannot delete closed opportunity for a banking account');
                }
            }
        }
    }

    protected override void afterInsert() {
        List<Task> newTasks = new List<Task>();
        // Create a new Task for newly inserted Opportunities
        for (Opportunity opp : (List<Opportunity>) Trigger.new) {
            Task tsk = new Task();
            tsk.Subject = 'Call Primary Contact';
            tsk.WhatId = opp.Id;
            tsk.WhoId = opp.Primary_Contact__c;
            tsk.OwnerId = opp.OwnerId;
            tsk.ActivityDate = Date.today().addDays(3);
            newTasks.add(tsk);
        }

        insert newTasks;
    }

    protected override void afterDelete() {
        notifyOwnersOpportunityDeleted((List<Opportunity>) Trigger.old);
    }

    protected override void afterUndelete() {
         assignPrimaryContact((Map<id, Opportunity>)Trigger.newMap);
    }

    /*
    notifyOwnersOpportunityDeleted:
    - Sends an email notification to the owner of the Opportunity when it gets deleted.
    - Uses Salesforce's Messaging.SingleEmailMessage to send the email.
    */
    private static void notifyOwnersOpportunityDeleted(List<Opportunity> opps) {
        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        Set<Id> oppOwnerIds = new Set<Id>();

        for (Opportunity opp: opps) {
            if (opp.OwnerId != null) {
                oppOwnerIds.add(opp.OwnerId);
            }
        }
        Map<Id, User> oppOwnerIdToOwnerMap = new Map<Id, User>([SELECT Id, Email FROM User WHERE Id IN :oppOwnerIds]);

        for (Opportunity opp : opps) {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            //String[] toAddresses = new String[] {[SELECT Id, Email FROM User WHERE Id = :opp.OwnerId].Email};
            if(oppOwnerIdToOwnerMap.containsKey(opp.OwnerId)){
                 mail.setToAddresses(new String[]{oppOwnerIdToOwnerMap.get(opp.OwnerId).Email});
            }
            mail.setSubject('Opportunity Deleted : ' + opp.Name);
            mail.setPlainTextBody('Your Opportunity: ' + opp.Name +' has been deleted.');
            mails.add(mail);
        }        
        
        try {
            Messaging.sendEmail(mails);
        } catch (Exception e){
            System.debug('Exception: ' + e.getMessage());
        }
    }

    /*
    assignPrimaryContact:
    - Assigns a primary contact with the title of 'VP Sales' to undeleted Opportunities.
    - Only updates the Opportunities that don't already have a primary contact.
    */
    private static void assignPrimaryContact(Map<Id,Opportunity> oppNewMap) {        
        Set<Id> accIds = new Set<Id>();

        for (Opportunity opp : oppNewMap.values()) {
            if (opp.accountId != null) {
                accIds.add(opp.accountId);
            }
        }
        Map<Id, Contact> accIdToContactMap = new Map<Id, Contact>();
        List<Contact> consList = [SELECT Id, AccountId FROM Contact WHERE Title = 'VP Sales' AND AccountId IN :accIds];

        for (Contact con: consList) {
            if (!accIdToContactMap.containsKey(con.AccountId)) {
                accIdToContactMap.put(con.AccountId, con);
            }
        }

        Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>();

        for (Opportunity opp : oppNewMap.values()) { 
            Contact primaryContact = null;
            if (accIdToContactMap.containsKey(opp.AccountId)) {
                primaryContact = accIdToContactMap.get(opp.AccountId);
            }          
            //Contact primaryContact = [SELECT Id, AccountId FROM Contact WHERE Title = 'VP Sales' AND AccountId = :opp.AccountId LIMIT 1];
            if (opp.Primary_Contact__c == null && primaryContact != null) {
                Opportunity updatedOpp = new Opportunity(Id = opp.Id);
                updatedOpp.Primary_Contact__c = primaryContact.Id;
                oppMap.put(opp.Id, updatedOpp);
            }
        }
        update oppMap.values();
    }
}