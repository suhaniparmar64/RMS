public without sharing class RMSPortalController {

    @AuraEnabled(cacheable=true)
    public static List<Job_Position__c> getOpenJobPositions() {
        return [
            SELECT Id, Name, Job_Code__c, Status__c, Location__c, Required_Skills__c,
                   Experience_Required__c, Job_Description__c, Posted_Date__c, Closing_Date__c, Openings__c,
                   Min_Salary__c, Max_Salary__c
            FROM Job_Position__c
            WHERE Status__c = 'Open'
            ORDER BY Posted_Date__c DESC, Name ASC
        ];
    }

    @AuraEnabled
    public static String submitApplication(
        String jobId, 
        String name, 
        String email, 
        String phone, 
        String experience, 
        String noticePeriod, 
        String linkedinUrl, 
        String coverLetter
    ) {
        try {
            // Find Job Position by Job Code or ID
            List<Job_Position__c> jobs = [
                SELECT Id, Name, Job_Code__c 
                FROM Job_Position__c 
                WHERE Id = :jobId OR Job_Code__c = :jobId 
                LIMIT 1
            ];
            if (jobs.isEmpty()) {
                throw new AuraHandledException('Job Position not found with ID/Code: ' + jobId);
            }
            Job_Position__c job = jobs[0];
            
            // Map Notice Period to picklist values
            String mappedNoticePeriod = '1 Month';
            String rawNotice = String.isNotBlank(noticePeriod) ? noticePeriod.toLowerCase() : '';
            if (rawNotice.contains('immediate') || rawNotice.contains('1 week')) {
                mappedNoticePeriod = '1 Week';
            } else if (rawNotice.contains('2 week') || rawNotice.contains('15 day')) {
                mappedNoticePeriod = '15 Days';
            } else if (rawNotice.contains('1 month')) {
                mappedNoticePeriod = '1 Month';
            } else if (rawNotice.contains('2 month')) {
                mappedNoticePeriod = '2 Month';
            } else if (rawNotice.contains('3 month')) {
                mappedNoticePeriod = '3 Month';
            }
            
            // Parse Experience Years
            Decimal experienceYears = 0;
            String rawExp = String.isNotBlank(experience) ? experience.toLowerCase() : '';
            Pattern p = Pattern.compile('(\\d+)');
            Matcher m = p.matcher(rawExp);
            if (m.find()) {
                experienceYears = Decimal.valueOf(m.group(1));
            }
            if (experienceYears == 0) {
                experienceYears = 1;
            }
            
            // 1. Create/Update Candidate record
            Candidate__c candidate = new Candidate__c();
            List<Candidate__c> existingCands = [
                SELECT Id FROM Candidate__c 
                WHERE Email__c = :email 
                LIMIT 1
            ];
            
            candidate.Full_Name__c = name;
            candidate.Email__c = email;
            candidate.Phone__c = phone;
            candidate.LinkedIn_URL__c = linkedinUrl;
            candidate.Experience_Years__c = experienceYears;
            candidate.Notice_Period__c = mappedNoticePeriod;
            candidate.Candidate_Status__c = 'New';
            candidate.Skills_Summary__c = 'Applied via RMS Digital Experience Portal. Cover Letter: ' + (String.isNotBlank(coverLetter) ? coverLetter : '');
            candidate.Source__c = 'RMS Portal';
            
            if (!existingCands.isEmpty()) {
                candidate.Id = existingCands[0].Id;
                update candidate;
            } else {
                insert candidate;
            }
            
            // 2. Create/Update Job Application record
            Job_Application__c app = new Job_Application__c();
            List<Job_Application__c> existingApps = [
                SELECT Id FROM Job_Application__c 
                WHERE Candidate__c = :candidate.Id AND Job_Position__c = :job.Id 
                LIMIT 1
            ];
            
            app.Candidate__c = candidate.Id;
            app.Job_Position__c = job.Id;
            app.Applied_Date__c = System.today();
            app.Application_Status__c = 'Applied';
            
            if (!existingApps.isEmpty()) {
                app.Id = existingApps[0].Id;
                update app;
            } else {
                insert app;
            }
            
            return app.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static List<JobApplicationWrapper> getJobApplications() {
        try {
            List<Job_Application__c> apps = [
                SELECT Id, Name, Applied_Date__c, Application_Status__c, Selected_for_Interview__c, AI_Match_Score__c,
                       Candidate__r.Full_Name__c, Candidate__r.Email__c, Candidate__r.Phone__c, 
                       Candidate__r.LinkedIn_URL__c, Candidate__r.Experience_Years__c, Candidate__r.Notice_Period__c,
                       Candidate__r.Skills_Summary__c,
                       Job_Position__r.Name, Job_Position__r.Job_Code__c, Job_Position__r.Location__c
                FROM Job_Application__c
                ORDER BY Applied_Date__c DESC, Name DESC
            ];

            List<JobApplicationWrapper> wrappedList = new List<JobApplicationWrapper>();
            for (Job_Application__c app : apps) {
                wrappedList.add(new JobApplicationWrapper(app));
            }
            return wrappedList;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void updateApplicationStatus(String applicationId, String status) {
        try {
            Job_Application__c app = new Job_Application__c(
                Id = applicationId,
                Application_Status__c = status,
                Selected_for_Interview__c = (status == 'Interview Scheduled')
            );
            update app;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String scheduleInterview(
        String applicationId,
        String scheduledDateTime,
        Integer duration,
        String mode,
        String meetingLink,
        String notes
    ) {
        try {
            // Parse ISO Datetime string (e.g. 2026-05-30T10:00:00.000Z)
            DateTime parsedDateTime = DateTime.valueOfGmt(scheduledDateTime.replace('T', ' ').replace('.000Z', '').substring(0, 19));
            
            Interview__c newInterview = new Interview__c();
            newInterview.Name = 'Interview: ' + [SELECT Candidate__r.Full_Name__c FROM Job_Application__c WHERE Id = :applicationId].Candidate__r.Full_Name__c;
            newInterview.Job_Application__c = applicationId;
            newInterview.Scheduled_DateTime__c = parsedDateTime;
            newInterview.Interview_Duration__c = duration;
            newInterview.Interview_Mode__c = mode;
            newInterview.Meeting_Link__c = meetingLink;
            newInterview.Interview_Notes__c = notes;
            newInterview.Interview_Status__c = 'Scheduled';
            newInterview.Interviewer__c = UserInfo.getUserId();
            
            insert newInterview;
            
            // Auto update application status
            updateApplicationStatus(applicationId, 'Interview Scheduled');
            
            return newInterview.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String createJobPosition(
        String title,
        Decimal experience,
        Decimal minSalary,
        Decimal maxSalary,
        String location,
        Integer openings,
        String description,
        String requiredSkills
    ) {
        try {
            Job_Position__c job = new Job_Position__c(
                Name = title,
                Experience_Required__c = experience,
                Min_Salary__c = minSalary,
                Max_Salary__c = maxSalary,
                Location__c = location,
                Openings__c = openings,
                Job_Description__c = description,
                Required_Skills__c = requiredSkills,
                Status__c = 'Open',
                Posted_Date__c = System.today()
            );
            insert job;
            return job.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static CandidateProfileWrapper getCandidateProfileAndApplications(String email) {
        try {
            List<Candidate__c> candidates = [
                SELECT Id, Full_Name__c, Email__c, Phone__c, LinkedIn_URL__c, Experience_Years__c, Notice_Period__c, Skills_Summary__c, Resume_URL__c
                FROM Candidate__c
                WHERE Email__c = :email
                LIMIT 1
            ];
            if (candidates.isEmpty()) {
                return null;
            }
            Candidate__c cand = candidates[0];
            
            List<Job_Application__c> apps = [
                SELECT Id, Name, Applied_Date__c, Application_Status__c, AI_Match_Score__c,
                       Job_Position__r.Name, Job_Position__r.Location__c, Job_Position__r.Job_Code__c
                FROM Job_Application__c
                WHERE Candidate__c = :cand.Id
                ORDER BY Applied_Date__c DESC
            ];
            
            return new CandidateProfileWrapper(cand, apps);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void updateCandidateProfile(
        String candidateId,
        String name,
        String phone,
        String linkedinUrl,
        Decimal experience,
        String noticePeriod,
        String skillsSummary
    ) {
        try {
            Candidate__c cand = new Candidate__c(
                Id = candidateId,
                Full_Name__c = name,
                Phone__c = phone,
                LinkedIn_URL__c = linkedinUrl,
                Experience_Years__c = experience,
                Notice_Period__c = noticePeriod,
                Skills_Summary__c = skillsSummary
            );
            update cand;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String uploadCandidateResume(
        String candidateId,
        String fileName,
        String base64Data,
        String contentType
    ) {
        try {
            // 1. Create ContentVersion (the file)
            ContentVersion cv = new ContentVersion();
            cv.Title = fileName;
            cv.PathOnClient = fileName;
            cv.VersionData = EncodingUtil.base64Decode(base64Data);
            cv.ContentLocation = 'S'; // 'S' = Salesforce (stored in SF)
            insert cv;

            // 2. Get the ContentDocumentId that was auto-created
            ContentVersion inserted = [
                SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1
            ];

            // 3. Link the file to the Candidate record
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = inserted.ContentDocumentId;
            cdl.LinkedEntityId = candidateId;
            cdl.ShareType = 'V'; // 'V' = Viewer
            cdl.Visibility = 'AllUsers';
            insert cdl;

            // 4. Optionally store the file URL on the Candidate record
            String fileUrl = '/sfc/servlet.shepherd/document/download/' + inserted.ContentDocumentId;
            Candidate__c cand = new Candidate__c(
                Id = candidateId,
                Resume_URL__c = fileUrl
            );
            update cand;

            return inserted.ContentDocumentId;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public class CandidateProfileWrapper {
        @AuraEnabled public String candidateId {get;set;}
        @AuraEnabled public String fullName {get;set;}
        @AuraEnabled public String email {get;set;}
        @AuraEnabled public String phone {get;set;}
        @AuraEnabled public String linkedinUrl {get;set;}
        @AuraEnabled public Decimal experienceYears {get;set;}
        @AuraEnabled public String noticePeriod {get;set;}
        @AuraEnabled public String skillsSummary {get;set;}
        @AuraEnabled public String resumeUrl {get;set;}
        @AuraEnabled public List<CandidateApplicationWrapper> applications {get;set;}
        
        public CandidateProfileWrapper(Candidate__c cand, List<Job_Application__c> apps) {
            this.candidateId = cand.Id;
            this.fullName = cand.Full_Name__c;
            this.email = cand.Email__c;
            this.phone = cand.Phone__c;
            this.linkedinUrl = cand.LinkedIn_URL__c;
            this.experienceYears = cand.Experience_Years__c;
            this.noticePeriod = cand.Notice_Period__c;
            this.skillsSummary = cand.Skills_Summary__c;
            this.resumeUrl = cand.Resume_URL__c;
            
            this.applications = new List<CandidateApplicationWrapper>();
            for (Job_Application__c app : apps) {
                this.applications.add(new CandidateApplicationWrapper(app));
            }
        }
    }
    
    public class CandidateApplicationWrapper {
        @AuraEnabled public String id {get;set;}
        @AuraEnabled public String name {get;set;}
        @AuraEnabled public Date appliedDate {get;set;}
        @AuraEnabled public String status {get;set;}
        @AuraEnabled public Decimal matchScore {get;set;}
        @AuraEnabled public String jobTitle {get;set;}
        @AuraEnabled public String jobLocation {get;set;}
        @AuraEnabled public String jobCode {get;set;}
        
        public CandidateApplicationWrapper(Job_Application__c app) {
            this.id = app.Id;
            this.name = app.Name;
            this.appliedDate = app.Applied_Date__c;
            this.status = app.Application_Status__c;
            this.matchScore = app.AI_Match_Score__c;
            this.jobTitle = app.Job_Position__r.Name;
            this.jobLocation = app.Job_Position__r.Location__c;
            this.jobCode = app.Job_Position__r.Job_Code__c;
        }
    }

    public class JobApplicationWrapper {
        @AuraEnabled public String id {get;set;}
        @AuraEnabled public String name {get;set;}
        @AuraEnabled public Date appliedDate {get;set;}
        @AuraEnabled public String status {get;set;}
        @AuraEnabled public Boolean selectedForInterview {get;set;}
        @AuraEnabled public Decimal matchScore {get;set;}
        @AuraEnabled public String candidateName {get;set;}
        @AuraEnabled public String candidateEmail {get;set;}
        @AuraEnabled public String candidatePhone {get;set;}
        @AuraEnabled public String candidateLinkedin {get;set;}
        @AuraEnabled public Decimal candidateExperience {get;set;}
        @AuraEnabled public String candidateNotice {get;set;}
        @AuraEnabled public String candidateSkillsSummary {get;set;}
        @AuraEnabled public String jobTitle {get;set;}
        @AuraEnabled public String jobCode {get;set;}
        @AuraEnabled public String jobLocation {get;set;}

        public JobApplicationWrapper(Job_Application__c app) {
            this.id = app.Id;
            this.name = app.Name;
            this.appliedDate = app.Applied_Date__c;
            this.status = app.Application_Status__c;
            this.selectedForInterview = app.Selected_for_Interview__c;
            this.matchScore = app.AI_Match_Score__c;
            this.candidateName = app.Candidate__r.Full_Name__c;
            this.candidateEmail = app.Candidate__r.Email__c;
            this.candidatePhone = app.Candidate__r.Phone__c;
            this.candidateLinkedin = app.Candidate__r.LinkedIn_URL__c;
            this.candidateExperience = app.Candidate__r.Experience_Years__c;
            this.candidateNotice = app.Candidate__r.Notice_Period__c;
            this.candidateSkillsSummary = app.Candidate__r.Skills_Summary__c;
            this.jobTitle = app.Job_Position__r.Name;
            this.jobCode = app.Job_Position__r.Job_Code__c;
            this.jobLocation = app.Job_Position__r.Location__c;
        }
    }
}
