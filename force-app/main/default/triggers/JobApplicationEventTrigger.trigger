trigger JobApplicationEventTrigger on Job_Application_Event__e (after insert) {
    List<String> emails = new List<String>();
    List<String> jobCodes = new List<String>();
    
    for (Job_Application_Event__e event : Trigger.new) {
        if (String.isNotBlank(event.Candidate_Email__c)) {
            emails.add(event.Candidate_Email__c);
        }
        if (String.isNotBlank(event.Job_Code__c)) {
            jobCodes.add(event.Job_Code__c);
        }
    }
    
    // 1. Query existing Candidates
    Map<String, Candidate__c> emailToCandidateMap = new Map<String, Candidate__c>();
    if (!emails.isEmpty()) {
        for (Candidate__c c : [SELECT Id, Email__c, Full_Name__c FROM Candidate__c WHERE Email__c IN :emails]) {
            emailToCandidateMap.put(c.Email__c, c);
        }
    }
    
    // 2. Query Job Positions (by Job_Code__c or Id)
    Map<String, Job_Position__c> codeToJobMap = new Map<String, Job_Position__c>();
    if (!jobCodes.isEmpty()) {
        for (Job_Position__c j : [SELECT Id, Job_Code__c, Name FROM Job_Position__c WHERE Job_Code__c IN :jobCodes OR Id IN :jobCodes]) {
            codeToJobMap.put(j.Job_Code__c, j);
            codeToJobMap.put(j.Id, j);
        }
    }
    
    // 3. Create missing Candidates
    List<Candidate__c> newCandidates = new List<Candidate__c>();
    List<Job_Application_Event__e> eventsToProcess = new List<Job_Application_Event__e>();
    
    for (Job_Application_Event__e event : Trigger.new) {
        if (String.isBlank(event.Candidate_Email__c) || String.isBlank(event.Job_Code__c)) {
            continue; // Skip invalid events
        }
        
        eventsToProcess.add(event);
        
        if (!emailToCandidateMap.containsKey(event.Candidate_Email__c)) {
            Candidate__c newCand = new Candidate__c();
            newCand.Full_Name__c = event.Candidate_Name__c;
            newCand.Email__c = event.Candidate_Email__c;
            newCand.Phone__c = event.Candidate_Phone__c;
            newCand.LinkedIn_URL__c = event.LinkedIn_URL__c;
            newCand.Experience_Years__c = event.Experience_Years__c;
            newCand.Notice_Period__c = event.Notice_Period__c;
            newCand.Candidate_Status__c = 'New';
            newCand.Skills_Summary__c = 'Applied via TalentBridge Portal. Cover Letter: ' + (event.Cover_Letter__c != null ? event.Cover_Letter__c : '');
            
            newCandidates.add(newCand);
            // Put placeholder in map to avoid duplicates within the same batch
            emailToCandidateMap.put(event.Candidate_Email__c, newCand);
        }
    }
    
    if (!newCandidates.isEmpty()) {
        insert newCandidates;
        // Refill emailMap with actual inserted records (to get IDs)
        for (Candidate__c c : newCandidates) {
            emailToCandidateMap.put(c.Email__c, c);
        }
    }
    
    // 4. Create Job Applications
    List<Job_Application__c> newApps = new List<Job_Application__c>();
    
    for (Job_Application_Event__e event : eventsToProcess) {
        Candidate__c cand = emailToCandidateMap.get(event.Candidate_Email__c);
        Job_Position__c job = codeToJobMap.get(event.Job_Code__c);
        
        if (cand != null && job != null) {
            Job_Application__c newApp = new Job_Application__c();
            newApp.Candidate__c = cand.Id;
            newApp.Job_Position__c = job.Id;
            newApp.Applied_Date__c = System.today();
            newApp.Application_Status__c = 'Applied';
            newApp.Selected_for_Interview__c = false;
            
            newApps.add(newApp);
        }
    }
    
    if (!newApps.isEmpty()) {
        insert newApps;
        
        // 5. Asynchronously (or synchronously here) calculate match score for each application
        // To avoid governor limits, we call our calculate method for each newly created application
        for (Job_Application__c app : newApps) {
            RecruitmentPortalAPI.calculateMatchScore(app.Id);
        }
    }
}
