import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getJobApplications from '@salesforce/apex/RMSPortalController.getJobApplications';
import updateApplicationStatus from '@salesforce/apex/RMSPortalController.updateApplicationStatus';
import scheduleInterview from '@salesforce/apex/RMSPortalController.scheduleInterview';
import createJobPosition from '@salesforce/apex/RMSPortalController.createJobPosition';

const STATUS_VALUES = ['Applied', 'Under Review', 'Interview Scheduled', 'Offer Released', 'Rejected'];

export default class RecruitmentAdminDashboard extends LightningElement {
    @track activeTab = 'applications'; // 'applications' or 'jobs'
    @track searchKey = '';
    @track rawApplications = [];
    @track filteredApplications = [];
    
    // Wire cache tracker for refreshing
    wiredAppsResult;

    // View Profile Modal
    @track isProfileModalOpen = false;
    @track selectedApp = {};

    // Interview Modal
    @track isInterviewModalOpen = false;
    @track isSubmittingInterview = false;
    @track interviewAlert = false;
    @track interviewAlertMessage = '';
    @track interviewAlertClass = '';

    // Job Creation Form
    @track isCreatingJob = false;
    @track jobAlert = false;
    @track jobAlertMessage = '';
    @track jobAlertClass = '';

    @wire(getJobApplications)
    wiredApplications(result) {
        this.wiredAppsResult = result;
        const { error, data } = result;
        if (data) {
            this.rawApplications = data.map(app => {
                // Determine AI Match Score classes
                let matchScoreClass = 'badge-score score-neutral';
                if (app.matchScore >= 80) {
                    matchScoreClass = 'badge-score score-high';
                } else if (app.matchScore >= 50) {
                    matchScoreClass = 'badge-score score-medium';
                } else if (app.matchScore > 0) {
                    matchScoreClass = 'badge-score score-low';
                }

                const formattedScore = app.matchScore != null ? `${app.matchScore}%` : 'N/A';
                
                // Form select option list with current value marked 'selected'
                const statusOptions = STATUS_VALUES.map(status => {
                    return {
                        label: status,
                        value: status,
                        isSelected: app.status === status
                    };
                });

                // Schedule button is disabled for final stages
                const isInterviewDisabled = app.status === 'Rejected' || app.status === 'Offer Released';

                return {
                    ...app,
                    matchScoreClass,
                    formattedScore,
                    statusOptions,
                    isInterviewDisabled
                };
            });
            this.filterApplications();
        } else if (error) {
            console.error('Error fetching applications:', error);
        }
    }

    // Tabs control classes
    get applicationsTabClass() {
        return `slds-tabs_default__item ${this.activeTab === 'applications' ? 'slds-is-active active-tab-premium' : ''}`;
    }

    get jobsTabClass() {
        return `slds-tabs_default__item ${this.activeTab === 'jobs' ? 'slds-is-active active-tab-premium' : ''}`;
    }

    get isApplicationsTabActive() {
        return this.activeTab === 'applications';
    }

    get isJobsTabActive() {
        return this.activeTab === 'jobs';
    }

    setActiveTabApplications() {
        this.activeTab = 'applications';
    }

    setActiveTabJobs() {
        this.activeTab = 'jobs';
        this.jobAlert = false;
        this.isCreatingJob = false;
    }

    get hasApplications() {
        return this.filteredApplications.length > 0;
    }

    get filteredAppsCount() {
        return this.filteredApplications.length;
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value;
        this.filterApplications();
    }

    filterApplications() {
        const query = this.searchKey.toLowerCase().trim();
        if (!query) {
            this.filteredApplications = [...this.rawApplications];
        } else {
            this.filteredApplications = this.rawApplications.filter(app => {
                const candNameMatch = app.candidateName && app.candidateName.toLowerCase().includes(query);
                const jobTitleMatch = app.jobTitle && app.jobTitle.toLowerCase().includes(query);
                const statusMatch = app.status && app.status.toLowerCase().includes(query);
                return candNameMatch || jobTitleMatch || statusMatch;
            });
        }
    }

    // Change candidate status
    async handleStatusChange(event) {
        const appId = event.target.dataset.id;
        const newStatus = event.target.value;

        try {
            await updateApplicationStatus({ applicationId: appId, status: newStatus });
            // Refresh table
            await refreshApex(this.wiredAppsResult);
        } catch (error) {
            console.error('Error updating status:', error);
        }
    }

    // View Profile modal
    handleViewProfile(event) {
        const appId = event.target.dataset.id;
        this.selectedApp = this.rawApplications.find(app => app.id === appId);
        this.isProfileModalOpen = true;
    }

    closeProfileModal() {
        this.isProfileModalOpen = false;
    }

    // Schedule Interview Modal
    handleOpenInterviewModal(event) {
        const appId = event.target.dataset.id;
        this.selectedApp = this.rawApplications.find(app => app.id === appId);
        this.isInterviewModalOpen = true;
        this.interviewAlert = false;
        this.isSubmittingInterview = false;
    }

    closeInterviewModal() {
        this.isInterviewModalOpen = false;
    }

    async handleInterviewSubmit() {
        const dtInput = this.template.querySelector('[data-id="intDateTime"]');
        const durInput = this.template.querySelector('[data-id="intDuration"]');
        const modeInput = this.template.querySelector('[data-id="intMode"]');
        const linkInput = this.template.querySelector('[data-id="intLink"]');
        const notesInput = this.template.querySelector('[data-id="intNotes"]');

        if (!dtInput.value) {
            this.showInterviewAlert('Please select a valid interview date and time.', 'alert-error');
            return;
        }

        this.isSubmittingInterview = true;
        this.interviewAlert = false;

        try {
            // Datetime local value format: "2026-05-30T10:00"
            // Convert to format "yyyy-MM-dd HH:mm:ss.SSSZ" expected by controller
            const rawDt = dtInput.value; // e.g. "2026-05-30T10:00"
            const formattedDt = `${rawDt.replace('T', ' ')}:00.000Z`;

            await scheduleInterview({
                applicationId: this.selectedApp.id,
                scheduledDateTime: formattedDt,
                duration: parseInt(durInput.value, 10),
                mode: modeInput.value,
                meetingLink: linkInput.value || '',
                notes: notesInput.value || ''
            });

            this.showInterviewAlert('Interview has been scheduled successfully!', 'alert-success');
            
            // Refresh table
            await refreshApex(this.wiredAppsResult);

            setTimeout(() => {
                this.closeInterviewModal();
            }, 2000);

        } catch (error) {
            console.error('Error scheduling interview:', error);
            const message = error.body && error.body.message ? error.body.message : 'An error occurred while scheduling. Please try again.';
            this.showInterviewAlert(message, 'alert-error');
            this.isSubmittingInterview = false;
        }
    }

    showInterviewAlert(message, cssClass) {
        this.interviewAlert = true;
        this.interviewAlertMessage = message;
        this.interviewAlertClass = `slds-p-around_small slds-m-bottom_medium ${cssClass}`;
    }

    // Job manager posting
    async handleJobSubmit() {
        const titleInput = this.template.querySelector('[data-id="jobTitleInput"]');
        const expInput = this.template.querySelector('[data-id="jobExpInput"]');
        const minSalaryInput = this.template.querySelector('[data-id="jobMinSalaryInput"]');
        const maxSalaryInput = this.template.querySelector('[data-id="jobMaxSalaryInput"]');
        const locInput = this.template.querySelector('[data-id="jobLocInput"]');
        const openingsInput = this.template.querySelector('[data-id="jobOpeningsInput"]');
        const skillsInput = this.template.querySelector('[data-id="jobSkillsInput"]');
        const descInput = this.template.querySelector('[data-id="jobDescInput"]');

        if (!titleInput.value || !expInput.value || !minSalaryInput.value || !maxSalaryInput.value || !locInput.value || !openingsInput.value || !skillsInput.value || !descInput.value) {
            this.showJobAlert('Please fill in all job fields.', 'alert-error');
            return;
        }

        const minSalary = parseFloat(minSalaryInput.value);
        const maxSalary = parseFloat(maxSalaryInput.value);

        if (minSalary > maxSalary) {
            this.showJobAlert('Minimum Salary cannot be greater than Maximum Salary.', 'alert-error');
            return;
        }

        this.isCreatingJob = true;
        this.jobAlert = false;

        try {
            await createJobPosition({
                title: titleInput.value,
                experience: parseFloat(expInput.value),
                minSalary: minSalary,
                maxSalary: maxSalary,
                location: locInput.value,
                openings: parseInt(openingsInput.value, 10),
                description: descInput.value,
                requiredSkills: skillsInput.value
            });

            this.showJobAlert('Job listing posted successfully!', 'alert-success');
            
            // Clear fields
            titleInput.value = '';
            expInput.value = '';
            minSalaryInput.value = '';
            maxSalaryInput.value = '';
            locInput.value = '';
            openingsInput.value = '';
            skillsInput.value = '';
            descInput.value = '';

            this.isCreatingJob = false;
        } catch (error) {
            console.error('Error creating job:', error);
            const message = error.body && error.body.message ? error.body.message : 'An error occurred while creating job. Please try again.';
            this.showJobAlert(message, 'alert-error');
            this.isCreatingJob = false;
        }
    }

    showJobAlert(message, cssClass) {
        this.jobAlert = true;
        this.jobAlertMessage = message;
        this.jobAlertClass = `slds-p-around_small slds-m-bottom_medium ${cssClass}`;
    }
}
