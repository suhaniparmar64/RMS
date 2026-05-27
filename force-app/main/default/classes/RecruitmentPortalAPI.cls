@RestResource(urlMapping='/RecruitmentPortalAPI/*')
global with sharing class RecruitmentPortalAPI {

    @HttpPost
    global static MatchResult calculateMatchScore(String applicationId) {
        MatchResult result = new MatchResult();
        
        try {
            // 1. Query the job application with related candidate and job position
            List<Job_Application__c> apps = [
                SELECT Id, Name, Candidate__c, Job_Position__c, AI_Match_Score__c,
                       Candidate__r.Full_Name__c, Candidate__r.Experience_Years__c, Candidate__r.Skills_Summary__c,
                       Job_Position__r.Name, Job_Position__r.Experience_Required__c, Job_Position__r.Required_Skills__c
                FROM Job_Application__c
                WHERE Id = :applicationId
                LIMIT 1
            ];
            
            if (apps.isEmpty()) {
                result.success = false;
                result.message = 'Job Application not found with ID: ' + applicationId;
                return result;
            }
            
            Job_Application__c app = apps[0];
            Decimal experienceScore = 0;
            Decimal skillsScore = 0;
            
            // 2. Compute Experience Score (up to 50 points)
            Decimal candidateExp = app.Candidate__r.Experience_Years__c != null ? app.Candidate__r.Experience_Years__c : 0;
            Decimal requiredExp = app.Job_Position__r.Experience_Required__c != null ? app.Job_Position__r.Experience_Required__c : 0;
            
            if (requiredExp == 0) {
                experienceScore = 50; // No experience required, full points
            } else if (candidateExp >= requiredExp) {
                experienceScore = 50; // Candidate has enough experience
            } else {
                // Proportional score
                experienceScore = (candidateExp / requiredExp) * 50;
            }
            
            // 3. Compute Skills Score (up to 50 points)
            String candidateSkills = app.Candidate__r.Skills_Summary__c != null ? app.Candidate__r.Skills_Summary__c.toLowerCase() : '';
            String requiredSkills = app.Job_Position__r.Required_Skills__c != null ? app.Job_Position__r.Required_Skills__c.toLowerCase() : '';
            
            if (String.isBlank(requiredSkills)) {
                skillsScore = 50; // No skills required, full points
            } else {
                // Split by common delimiters (commas, semicolons, newlines)
                List<String> reqSkillsList = requiredSkills.split('[,;\\n]+');
                Integer matchedCount = 0;
                Integer totalSkillsCount = 0;
                
                for (String reqSkill : reqSkillsList) {
                    String cleanSkill = reqSkill.trim();
                    if (String.isNotBlank(cleanSkill)) {
                        totalSkillsCount++;
                        if (candidateSkills.contains(cleanSkill)) {
                            matchedCount++;
                        }
                    }
                }
                
                if (totalSkillsCount > 0) {
                    skillsScore = ((Decimal)matchedCount / (Decimal)totalSkillsCount) * 50;
                } else {
                    skillsScore = 50;
                }
            }
            
            // 4. Calculate Final Percentage Match (0 - 100)
            Decimal totalScore = experienceScore + skillsScore;
            // Round to 2 decimal places
            totalScore = totalScore.setScale(2, System.RoundingMode.HALF_UP);
            
            // 5. Update the Job Application record
            app.AI_Match_Score__c = totalScore;
            update app;
            
            // 6. Create a Notification Log record
            Notification_Log__c log = new Notification_Log__c();
            log.Name = 'Match Calc: ' + app.Candidate__r.Full_Name__c + ' - ' + totalScore + '%';
            insert log;
            
            result.success = true;
            result.message = 'Match score calculated and updated successfully.';
            result.matchScore = totalScore;
            result.applicationId = app.Id;
            result.candidateName = app.Candidate__r.Full_Name__c;
            result.jobTitle = app.Job_Position__r.Name;
            
        } catch (Exception e) {
            result.success = false;
            result.message = 'Error during match calculation: ' + e.getMessage() + '\n' + e.getStackTraceString();
            System.debug('RecruitmentPortalAPI Error: ' + e.getMessage());
        }
        
        return result;
    }
    
    global class MatchResult {
        @AuraEnabled global Boolean success {get; set;}
        @AuraEnabled global String message {get; set;}
        @AuraEnabled global Decimal matchScore {get; set;}
        @AuraEnabled global String applicationId {get; set;}
        @AuraEnabled global String candidateName {get; set;}
        @AuraEnabled global String jobTitle {get; set;}
    }
}
