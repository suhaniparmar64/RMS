import { LightningElement, wire, track } from 'lwc';
import getOpenJobPositions from '@salesforce/apex/RMSPortalController.getOpenJobPositions';
import submitApplication from '@salesforce/apex/RMSPortalController.submitApplication';
import getCandidateProfileAndApplications from '@salesforce/apex/RMSPortalController.getCandidateProfileAndApplications';
import updateCandidateProfile from '@salesforce/apex/RMSPortalController.updateCandidateProfile';
import uploadCandidateResume from '@salesforce/apex/RMSPortalController.uploadCandidateResume';

const NOTICE_VALUES = ['1 Week', '15 Days', '1 Month', '2 Month', '3 Month'];
const STEP_SEQUENCE = ['Applied', 'Under Review', 'Interview Scheduled', 'Offer Released'];

export default class RecruitmentPortal extends LightningElement {
    @track activeTab = 'jobs'; // 'jobs' or 'profile'
    @track searchKey = '';
    @track rawJobs = [];
    @track filteredJobs = [];
    @track selectedJob = null;
    @track isApplyModalOpen = false;
    @track isSubmitting = false;

    // Modal alerts
    @track modalAlert = false;
    @track modalAlertClass = '';
    @track modalAlertMessage = '';

    // Active Job
    @track selectedJobId = null;

    // Resume file state (apply modal)
    @track resumeFileName = '';
    resumeFileBase64 = null;
    resumeFileType = '';

    // Resume file state (profile section)
    @track profileResumeFileName = '';
    profileResumeFileBase64 = null;
    profileResumeFileType = '';
    @track isUploadingResume = false;
    @track resumeAlert = false;
    @track resumeAlertClass = '';
    @track resumeAlertMessage = '';

    // Candidate Profile login/access state
    @track candidateEmail = '';
    @track candidateProfile = null;
    @track isVerifying = false;
    @track verifyAlert = false;
    @track verifyAlertClass = '';
    @track verifyAlertMessage = '';

    // Candidate Profile update state
    @track isUpdatingProfile = false;
    @track profileAlert = false;
    @track profileAlertClass = '';
    @track profileAlertMessage = '';

    @wire(getOpenJobPositions)
    wiredJobs({ error, data }) {
        if (data) {
            this.rawJobs = data.map(job => {
                const skillsList = job.Required_Skills__c 
                    ? job.Required_Skills__c.split(/[,;]/).map(s => s.trim()).filter(Boolean) 
                    : [];
                
                // Format salary range
                let salaryRange = 'Competitive';
                if (job.Min_Salary__c && job.Max_Salary__c) {
                    salaryRange = `$${job.Min_Salary__c.toLocaleString()} - $${job.Max_Salary__c.toLocaleString()}`;
                } else if (job.Min_Salary__c) {
                    salaryRange = `$${job.Min_Salary__c.toLocaleString()}+`;
                }

                // Generate initials for the logo avatar
                const logo = job.Name 
                    ? job.Name.split(' ').map(w => w[0]).join('').substring(0, 2).toUpperCase() 
                    : 'JR';

                return {
                    ...job,
                    skillsList,
                    salaryRange,
                    logo,
                    cardClass: 'job-card slds-p-around_medium slds-m-bottom_medium'
                };
            });
            this.filterJobs();
            
            // Auto select first job
            if (this.filteredJobs.length > 0 && !this.selectedJobId) {
                this.selectJob(this.filteredJobs[0].Id);
            }
        } else if (error) {
            console.error('Error fetching job positions:', error);
        }
    }

    get hasJobs() {
        return this.filteredJobs.length > 0;
    }

    get filteredJobsCount() {
        return this.filteredJobs.length;
    }

    // Tabs Classes & Methods
    get jobsTabClass() {
        return `slds-tabs_default__item ${this.activeTab === 'jobs' ? 'slds-is-active active-tab-premium' : ''}`;
    }

    get profileTabClass() {
        return `slds-tabs_default__item ${this.activeTab === 'profile' ? 'slds-is-active active-tab-premium' : ''}`;
    }

    get isJobsTabActive() {
        return this.activeTab === 'jobs';
    }

    get isProfileTabActive() {
        return this.activeTab === 'profile';
    }

    setActiveTabJobs() {
        this.activeTab = 'jobs';
    }

    setActiveTabProfile() {
        this.activeTab = 'profile';
        this.verifyAlert = false;
        this.profileAlert = false;
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value;
        this.filterJobs();
    }

    filterJobs() {
        const query = this.searchKey.toLowerCase().trim();
        if (!query) {
            this.filteredJobs = [...this.rawJobs];
        } else {
            this.filteredJobs = this.rawJobs.filter(job => {
                const nameMatch = job.Name && job.Name.toLowerCase().includes(query);
                const locationMatch = job.Location__c && job.Location__c.toLowerCase().includes(query);
                const descMatch = job.Job_Description__c && job.Job_Description__c.toLowerCase().includes(query);
                const skillsMatch = job.Required_Skills__c && job.Required_Skills__c.toLowerCase().includes(query);
                return nameMatch || locationMatch || descMatch || skillsMatch;
            });
        }

        this.updateCardClasses();
        
        if (this.filteredJobs.length > 0) {
            const currentSelectedInFiltered = this.filteredJobs.find(j => j.Id === this.selectedJobId);
            if (!currentSelectedInFiltered) {
                this.selectJob(this.filteredJobs[0].Id);
            }
        } else {
            this.selectedJob = null;
            this.selectedJobId = null;
        }
    }

    handleJobSelect(event) {
        const jobId = event.currentTarget.dataset.id;
        this.selectJob(jobId);
    }

    selectJob(jobId) {
        this.selectedJobId = jobId;
        this.selectedJob = this.rawJobs.find(job => job.Id === jobId);
        this.updateCardClasses();
    }

    updateCardClasses() {
        this.filteredJobs = this.filteredJobs.map(job => {
            const isSelected = job.Id === this.selectedJobId;
            return {
                ...job,
                cardClass: `job-card slds-p-around_medium slds-m-bottom_medium ${isSelected ? 'selected' : ''}`
            };
        });
    }

    openApplyModal() {
        this.isApplyModalOpen = true;
        this.modalAlert = false;
        this.isSubmitting = false;
    }

    closeApplyModal() {
        this.isApplyModalOpen = false;
    }

    async handleFormSubmit() {
        const nameInput = this.template.querySelector('[data-id="candName"]');
        const emailInput = this.template.querySelector('[data-id="candEmail"]');
        const phoneInput = this.template.querySelector('[data-id="candPhone"]');
        const linkedinInput = this.template.querySelector('[data-id="candLinkedin"]');
        const expInput = this.template.querySelector('[data-id="candExp"]');
        const noticeInput = this.template.querySelector('[data-id="candNotice"]');
        const letterInput = this.template.querySelector('[data-id="candLetter"]');

        if (!nameInput.value || !emailInput.value || !phoneInput.value || !expInput.value) {
            this.showAlert('Please fill in all required fields.', 'alert-error');
            return;
        }

        if (!emailInput.checkValidity()) {
            this.showAlert('Please enter a valid email address.', 'alert-error');
            return;
        }

        this.isSubmitting = true;
        this.modalAlert = false;

        try {
            const appId = await submitApplication({
                jobId: this.selectedJob.Id,
                name: nameInput.value,
                email: emailInput.value,
                phone: phoneInput.value,
                experience: expInput.value,
                noticePeriod: noticeInput.value,
                linkedinUrl: linkedinInput.value || '',
                coverLetter: letterInput.value || ''
            });

            // If a resume was selected, upload it after the candidate record is created
            if (this.resumeFileBase64) {
                try {
                    // Find the newly created Candidate by email
                    const profileData = await getCandidateProfileAndApplications({ email: emailInput.value });
                    if (profileData && profileData.candidateId) {
                        await uploadCandidateResume({
                            candidateId: profileData.candidateId,
                            fileName: this.resumeFileName,
                            base64Data: this.resumeFileBase64,
                            contentType: this.resumeFileType
                        });
                    }
                } catch (resumeErr) {
                    console.warn('Resume upload failed (non-blocking):', resumeErr);
                }
            }

            this.showAlert('Your application has been submitted successfully! ✅', 'alert-success');

            // Auto login after application submission
            this.candidateEmail = emailInput.value;
            this.fetchProfileAndApplications(emailInput.value);

            // Reset resume state
            this.resumeFileName = '';
            this.resumeFileBase64 = null;

            setTimeout(() => {
                this.closeApplyModal();
            }, 2000);

        } catch (error) {
            console.error('Error submitting application:', error);
            const message = error.body && error.body.message ? error.body.message : 'An error occurred. Please try again.';
            this.showAlert(message, 'alert-error');
            this.isSubmitting = false;
        }
    }

    showAlert(message, cssClass) {
        this.modalAlert = true;
        this.modalAlertMessage = message;
        this.modalAlertClass = `slds-p-around_small slds-m-bottom_medium ${cssClass}`;
    }

    handleResumeFileChange(event) {
        const file = event.target.files[0];
        if (!file) return;
        if (file.size > 5 * 1024 * 1024) {
            this.showAlert('Resume file must be under 5 MB.', 'alert-error');
            return;
        }
        this.resumeFileName = file.name;
        this.resumeFileType = file.type;
        const reader = new FileReader();
        reader.onload = () => {
            // Strip the data:...;base64, prefix
            this.resumeFileBase64 = reader.result.split(',')[1];
        };
        reader.readAsDataURL(file);
    }

    handleProfileResumeChange(event) {
        const file = event.target.files[0];
        if (!file) return;
        if (file.size > 5 * 1024 * 1024) {
            this.showProfileAlert('Resume file must be under 5 MB.', 'alert-error');
            return;
        }
        this.profileResumeFileName = file.name;
        this.profileResumeFileType = file.type;
        const reader = new FileReader();
        reader.onload = () => {
            this.profileResumeFileBase64 = reader.result.split(',')[1];
        };
        reader.readAsDataURL(file);
    }

    async handleUploadProfileResume() {
        if (!this.profileResumeFileBase64) {
            this.showProfileAlert('Please select a resume file first.', 'alert-error');
            return;
        }
        this.isUploadingResume = true;
        this.profileAlert = false;
        try {
            await uploadCandidateResume({
                candidateId: this.candidateProfile.candidateId,
                fileName: this.profileResumeFileName,
                base64Data: this.profileResumeFileBase64,
                contentType: this.profileResumeFileType
            });
            this.showProfileAlert('Resume uploaded successfully! ✅', 'alert-success');
            // Refresh profile to get updated resumeUrl
            await this.fetchProfileAndApplications(this.candidateEmail);
            this.profileResumeFileName = '';
            this.profileResumeFileBase64 = null;
        } catch (error) {
            console.error('Resume upload error:', error);
            const message = error.body && error.body.message ? error.body.message : 'Failed to upload resume.';
            this.showProfileAlert(message, 'alert-error');
        } finally {
            this.isUploadingResume = false;
        }
    }

    // Candidate Verification & Login APIs
    async handleVerifyEmail() {
        const verifyInput = this.template.querySelector('[data-id="verifyEmailInput"]');
        if (!verifyInput.value || !verifyInput.checkValidity()) {
            this.showVerifyAlert('Please enter a valid email address.', 'alert-error');
            return;
        }

        this.isVerifying = true;
        this.verifyAlert = false;

        try {
            this.candidateEmail = verifyInput.value;
            await this.fetchProfileAndApplications(verifyInput.value);
            this.isVerifying = false;
        } catch (error) {
            console.error('Verify error:', error);
            this.showVerifyAlert('Error accessing portal. Please try again.', 'alert-error');
            this.isVerifying = false;
        }
    }

    async fetchProfileAndApplications(email) {
        try {
            const data = await getCandidateProfileAndApplications({ email: email });
            if (data) {
                // Map status progress tracker bar
                const applications = data.applications.map(app => {
                    // Status Badge Styling
                    let statusClass = 'badge-status status-applied';
                    if (app.status === 'Under Review') {
                        statusClass = 'badge-status status-review';
                    } else if (app.status === 'Interview Scheduled') {
                        statusClass = 'badge-status status-interview';
                    } else if (app.status === 'Offer Released') {
                        statusClass = 'badge-status status-offer';
                    } else if (app.status === 'Rejected') {
                        statusClass = 'badge-status status-rejected';
                    }

                    // Progress bar calculation
                    let activeIndex = STEP_SEQUENCE.indexOf(app.status);
                    if (app.status === 'Rejected') {
                        activeIndex = 3; // final step
                    }
                    if (activeIndex === -1) {
                        activeIndex = 0;
                    }

                    const progressPercentage = (activeIndex / 3) * 100;
                    const progressFillStyle = `width: ${progressPercentage}%`;

                    const steps = [
                        { label: 'Applied', icon: '✓', stepClass: 'progress-step' },
                        { label: 'Review', icon: '🔎', stepClass: 'progress-step' },
                        { label: 'Interview', icon: '📅', stepClass: 'progress-step' },
                        { label: app.status === 'Rejected' ? 'Rejected' : 'Decision', icon: app.status === 'Rejected' ? '✕' : '🎉', stepClass: 'progress-step' }
                    ];

                    // Assign completion classes to steps
                    steps.forEach((step, idx) => {
                        if (idx < activeIndex) {
                            step.stepClass += ' completed';
                        } else if (idx === activeIndex) {
                            step.stepClass += app.status === 'Rejected' ? ' rejected' : ' active';
                        } else {
                            step.stepClass += ' upcoming';
                        }
                    });

                    return {
                        ...app,
                        statusClass,
                        progressFillStyle,
                        steps
                    };
                });

                this.candidateProfile = {
                    ...data,
                    applications
                };
            } else {
                this.showVerifyAlert('No candidate profile found with this email. Please check your spelling or apply to a job first.', 'alert-error');
                this.candidateProfile = null;
            }
        } catch (error) {
            console.error('Error fetching candidate applications:', error);
            throw error;
        }
    }

    showVerifyAlert(message, cssClass) {
        this.verifyAlert = true;
        this.verifyAlertMessage = message;
        this.verifyAlertClass = `slds-p-around_small slds-m-bottom_medium ${cssClass}`;
    }

    handleLogout() {
        this.candidateProfile = null;
        this.candidateEmail = '';
        this.verifyAlert = false;
        this.profileAlert = false;
    }

    // Profile Initials & Notice picklist helper
    get profileInitials() {
        if (!this.candidateProfile || !this.candidateProfile.fullName) return 'C';
        return this.candidateProfile.fullName.split(' ').map(w => w[0]).join('').substring(0, 2).toUpperCase();
    }

    get hasApplications() {
        return this.candidateProfile && this.candidateProfile.applications && this.candidateProfile.applications.length > 0;
    }

    get noticeOptions() {
        if (!this.candidateProfile) return [];
        return NOTICE_VALUES.map(val => {
            return {
                label: val,
                value: val,
                isSelected: this.candidateProfile.noticePeriod === val
            };
        });
    }

    // Profile updates
    async handleUpdateProfile() {
        const nameInp = this.template.querySelector('[data-id="editName"]');
        const phoneInp = this.template.querySelector('[data-id="editPhone"]');
        const linkInp = this.template.querySelector('[data-id="editLinkedin"]');
        const expInp = this.template.querySelector('[data-id="editExp"]');
        const noticeInp = this.template.querySelector('[data-id="editNotice"]');
        const skillsInp = this.template.querySelector('[data-id="editSkills"]');

        if (!nameInp.value || !phoneInp.value || !expInp.value) {
            this.showProfileAlert('Name, Phone, and Experience are required.', 'alert-error');
            return;
        }

        this.isUpdatingProfile = true;
        this.profileAlert = false;

        try {
            await updateCandidateProfile({
                candidateId: this.candidateProfile.candidateId,
                name: nameInp.value,
                phone: phoneInp.value,
                linkedinUrl: linkInp.value || '',
                experience: parseFloat(expInp.value),
                noticePeriod: noticeInp.value,
                skillsSummary: skillsInp.value || ''
            });

            this.showProfileAlert('Profile updated successfully!', 'alert-success');
            
            // Reload updated details
            await this.fetchProfileAndApplications(this.candidateEmail);
            this.isUpdatingProfile = false;

        } catch (error) {
            console.error('Update profile error:', error);
            const message = error.body && error.body.message ? error.body.message : 'An error occurred during save. Please try again.';
            this.showProfileAlert(message, 'alert-error');
            this.isUpdatingProfile = false;
        }
    }

    showProfileAlert(message, cssClass) {
        this.profileAlert = true;
        this.profileAlertMessage = message;
        this.profileAlertClass = `slds-p-around_small slds-m-bottom_medium ${cssClass}`;
    }
}
