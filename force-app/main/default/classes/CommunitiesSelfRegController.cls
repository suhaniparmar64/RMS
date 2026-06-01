/**
 * An apex page controller that supports self registration of users in communities that allow self registration
 * Updated for RMS Experience Cloud site
 */
public class CommunitiesSelfRegController {

    public String firstName        { get; set; }
    public String lastName         { get; set; }
    public String email            { get; set; }
    public String password         { get; set { password        = value == null ? value : value.trim(); } }
    public String confirmPassword  { get; set { confirmPassword = value == null ? value : value.trim(); } }
    public String communityNickname{ get; set { communityNickname = value == null ? value : value.trim(); } }

    // RMS-specific IDs
    // Profile  : Customer Community User
    private static final String SELF_REG_PROFILE_ID = '00eg5000004biBZAAY';
    // Account  : RMS Candidates (dedicated account for portal self-reg)
    private static final String SELF_REG_ACCOUNT_ID = '001g500000PJI72AAH';

    public CommunitiesSelfRegController() {
        String expid = ApexPages.currentPage().getParameters().get('expid');
        if (expid != null) {
            Site.setExperienceId(expid);
        }
    }

    private Boolean isValidPassword() {
        return password == confirmPassword;
    }

    public PageReference registerUser() {

        // 1. Password match check
        if (!isValidPassword()) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR, Label.site.passwords_dont_match
            ));
            return null;
        }

        // 2. Required field validation
        if (String.isBlank(firstName) || String.isBlank(lastName) || String.isBlank(email)) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR, 'First name, last name, and email are required.'
            ));
            return null;
        }

        // 3. Build the user record
        User u = new User();
        u.Username          = email.trim().toLowerCase();
        u.Email             = email.trim().toLowerCase();
        u.FirstName         = firstName.trim();
        u.LastName          = lastName.trim();
        u.CommunityNickname = String.isBlank(communityNickname)
                                ? (firstName.trim() + lastName.trim()).left(40)
                                : communityNickname.trim();
        u.ProfileId         = SELF_REG_PROFILE_ID;

        String userId;

        try {
            // Pass null password so Salesforce sends the user an auto-generated
            // password / email-verification link (safer for portal sign-up)
            String pwd = (String.isBlank(password)) ? null : password;
            userId = Site.createExternalUser(u, SELF_REG_ACCOUNT_ID, pwd);

        } catch (Site.ExternalUserCreateException ex) {
            // Surface Salesforce's own validation messages to the user
            List<String> errors = ex.getDisplayMessages();
            for (String error : errors) {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, error));
            }
            System.debug('ExternalUserCreateException: ' + ex.getMessage());
            return null;

        } catch (Exception ex) {
            // Catch-all — log the real error instead of letting it bubble up
            // to the "site administrator has been alerted" page
            System.debug('Registration error: ' + ex.getMessage() + ' | Type: ' + ex.getTypeName());
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'Registration could not be completed: ' + ex.getMessage()
            ));
            return null;
        }

        // 4. On success — log in or redirect to confirmation
        if (userId != null) {
            String startURL = ApexPages.currentPage().getParameters().get('startURL');
            if (!String.isBlank(password) && password.length() > 1) {
                return Site.login(u.Username, password, startURL);
            } else {
                PageReference confirmPage = System.Page.CommunitiesSelfRegConfirm;
                confirmPage.setRedirect(true);
                return confirmPage;
            }
        }

        return null;
    }
}