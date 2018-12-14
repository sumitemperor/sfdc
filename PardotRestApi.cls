@RestResource(urlMapping='/sendEmail/*')
global with sharing class PardotRestApi {
    
    private static final String DEFAULT_SUBJECT = 'Pardot Notification';
    private static final String EMAIL_PARAM = 'email';
	private static final String NONE = 'NONE';
    private static final String SUBJECT_PARAM = 'subject';
    private static final String TEMPLATE_NAME_PARAM = 'templateName';
    private static final String PROSPECT_LINK_MARKER = '!prospect_link!';
    private static final String EMAIL_STATUS_ERROR = 'The email failed to send';
    private static final String EMAIL_STATUS_SUCCESS = 'The email was sent successfully.';
    
    private static final String DEFAULT_TEMPLATE_NAME = 'StandardTemplate';
    private static final String GOOD_FORMAT = 'SUCCESS: No Format Error';
    private static final String BAD_FORMAT = 'ERROR: Format not correct';
    
    public static final String LIMIT_EXCEEDED_ERROR = 'Number of emails sent Today is over the limit. Your registration was successful however system administrator may not be aware of your registration';
    public static final String EMAIL_ERROR = 'Error occured while sending notification. System administrator may not be aware of this registration.';
    public static final String SUCCESS_MESSAGE = 'Success';
    
    @HttpGet
    global static String sendEmail() {
        RestContext.response.addHeader('Access-Control-Allow-Origin', '*'); 
        
        if (isOverLimit()) {
			creatPardotEmailNotificationLog(EMAIL_ERROR, NONE, LIMIT_EXCEEDED_ERROR, NONE);
            return LIMIT_EXCEEDED_ERROR;
        }
        
        String recipients, exLog;
        String format = 'Success: No Format Error';
        
        try {
            Map<String, String> params = RestContext.request.params;
            String templateName = params.containsKey(TEMPLATE_NAME_PARAM) ? params.get(TEMPLATE_NAME_PARAM) : DEFAULT_TEMPLATE_NAME;
            PardotEmailTemplate__c templateInfo = getTemplateInfo(templateName);
            
            recipients = getEmailsForPosting(templateInfo);
            
            Messaging.SingleEmailMessage msg = prepareEmail(templateInfo.Id__c, getEmailsFromTemplateInfo(templateInfo), params);
			Messaging.SendEmailResult[] ser = Messaging.sendEmail(new List<Messaging.SingleEmailMessage> { msg }); 
                
            if (ser[0].isSuccess()) {
                creatPardotEmailNotificationLog(EMAIL_STATUS_SUCCESS, getEmailsForPosting(templateInfo), NONE, format);
            }else {
                creatPardotEmailNotificationLog(EMAIL_STATUS_ERROR, getEmailsForPosting(templateInfo), NONE, format);
            }

			incrementEmailCounter();
        } catch (Exception ex) {
            exLog = ex.getMessage();
            if(exLog.contains('INVALID_EMAIL_ADDRESS')) {
                creatPardotEmailNotificationLog(EMAIL_ERROR, recipients, exLog, BAD_FORMAT);
            }else {
                creatPardotEmailNotificationLog(EMAIL_ERROR, recipients, exLog, NONE);
            }
			
            return EMAIL_ERROR;
        }
        return SUCCESS_MESSAGE;
    }
    
    public static Messaging.SingleEmailMessage prepareEmail(Id templateId, List<String> recipients, Map<String, String> params) {
        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        EmailTemplate emailTemplate = [SELECT Id, Subject, HtmlValue, Body FROM EmailTemplate WHERE Id = : templateId];
        
        String htmlBody = Test.isRunningTest() ? 'TestBody !name! !email!' : emailTemplate.HtmlValue;
        for (String key : params.keySet()) {
            htmlBody = htmlBody.replaceAll('!' + key + '!', params.get(key));
        }
        
        if (params.containsKey(EMAIL_PARAM)) 
            htmlBody = htmlBody.replaceAll(PROSPECT_LINK_MARKER, '<a href="https://pi.pardot.com/search?query=' + params.get(EMAIL_PARAM) +'">Click here</a>');
        
        OrgWideEmailAddress[] fromAdd = [select Id from OrgWideEmailAddress where Address = 'pardotnotification@getnada.com'];

		if ( fromAdd.size() > 0 ) {
    		msg.setOrgWideEmailAddressId(fromAdd.get(0).Id);
		}
        
        msg.setToAddresses(recipients);
        msg.subject = params.containsKey(SUBJECT_PARAM) ? params.get(SUBJECT_PARAM) : DEFAULT_SUBJECT;
        msg.setHtmlBody(htmlBody);  
        
        return msg;
    }
    
    public static void incrementEmailCounter() {
        PardotLimitController__c limitInfo = PardotLimitController__c.getAll().values()[0];
        limitInfo.CurrentCount__c += 1;
        update limitInfo;
    }
    
    public static Boolean isOverLimit() {
        PardotLimitController__c limitInfo = PardotLimitController__c.getAll().values()[0];
        return (limitInfo.Limit__c < limitInfo.CurrentCount__c);
        
    }
    
    public static PardotEmailTemplate__c getTemplateInfo(String templateName) {
        List<PardotEmailTemplate__c> templateInfos = PardotEmailTemplate__c.getAll().values();
        PardotEmailTemplate__c stdTemplate;
        for (PardotEmailTemplate__c templateInfo : templateInfos) {
            if (templateInfo.Name == DEFAULT_TEMPLATE_NAME) stdTemplate = templateInfo;
            if (templateInfo.Name == templateName) return templateInfo; 
        }
        return stdTemplate;
    }
    
    public static List<String> getEmailsFromTemplateInfo(PardotEmailTemplate__c templateInfo) {
        return templateInfo.RecipientsEmails__c.split(' ');
    }
    
    public static void creatPardotEmailNotificationLog(String emailStatus, String recipients, String excpton, String format) {
    	Pardot_Email_Notification_Log__c newLog = new Pardot_Email_Notification_Log__c();
        newLog.Date_Sent__c = System.now();
        newLog.Email_Result__c = emailStatus;
        newLog.Recipients__c = recipients;
        newLog.Exception_Log__c = excpton;
        newLog.Email_Format_on_Custom_Settings__c = format;
        
        insert newLog;   
    }
    
    public static String getEmailsForPosting(PardotEmailTemplate__c templateInfo) {
        return templateInfo.RecipientsEmails__c.replace(' ','\r\n');
    }

}