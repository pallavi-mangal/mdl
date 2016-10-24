/* Send request to JIRA when new case is getting created/updated in Salesforce
 ** 'actionType' variable will define that it is a create request or Update request
 ** Author: Pallavi Mangal
 ** Date: 11/10/2015   
 */
global class JIRA {

    @future (callout=true) 
    WebService static void issueCreateUpdateSync(String objectId, String projectKey, String issueType, String actionType, String summary, 
                                                  String description, String jiraIssueId, String jiraComment, String jiraCommentId, String jiraCommentObjectId) {
        // get JIRA realted values from custom settings
        String baseJIRAUrl = Label.JIRA_Base_URL;
        String jiraUsername = Label.JIRA_Username;
        String jiraPassword = Label.JIRA_Password;
        String loggedInUser = UserInfo.getUserName();
        String issuesJson;
        String jiraKeyRes;
        String jiraIssueIdRes;
        HttpResponse res = new HttpResponse();

        try {
        	if (actionType == 'Create'){
	            HttpRequest req = buildRequest(baseJIRAUrl, jiraUsername, jiraPassword, objectId, projectKey, issueType, 
                                                loggedInUser, actionType, summary, description, jiraIssueId, jiraComment, jiraCommentId, jiraCommentObjectId);
	            //system.debug('Request***'+req);
	            res = sendRequest(req);
                System.debug('Response json****:'+res.getBody());
                issuesJson = res.getBody();

                Map<String, Object> mapJSON = (Map<String, Object>)JSON.deserializeUntyped(issuesJson);
                System.debug('Project Key:'+(String)mapJSON.get('key'));
                jiraKeyRes = (String)mapJSON.get('key');
                jiraIssueIdRes = (String)mapJSON.get('id');
                updateCase(objectId, jiraKeyRes, jiraIssueIdRes); 
	        }

            if (actionType == 'Update'){
	        	HttpRequest req = buildRequest(baseJIRAUrl, jiraUsername, jiraPassword, objectId, projectKey, 
                                                issueType, loggedInUser, actionType, summary, description, jiraIssueId, jiraComment, jiraCommentId, jiraCommentObjectId);
	            //system.debug('Request***'+req);
	            sendRequest(req);
			}

            if (actionType == 'CreateJIRAComment'){
                Case caseIssue = [Select JIRA_Issue_Id__c
                                  From Case
                                  Where Id =: objectId];
                //System.debug('Jira Issue Id***:'+caseIssue.JIRA_Issue_Id__c);
                HttpRequest req = buildRequest(baseJIRAUrl, jiraUsername, jiraPassword, objectId, projectKey, issueType, 
                                                loggedInUser, actionType, summary, description, caseIssue.JIRA_Issue_Id__c, jiraComment, jiraCommentId, jiraCommentObjectId);
                system.debug('Request***'+req);
                res = sendRequest(req);
                System.debug('Response json****:'+res.getBody());
                issuesJson = res.getBody();

                Map<String, Object> mapJSON = (Map<String, Object>)JSON.deserializeUntyped(issuesJson);
                System.debug('comment Id:'+(String)mapJSON.get('id'));
                String jiraIssueCommentIdRes = (String)mapJSON.get('id');

                Map<String, Object> receivedUpdateAuthor = (Map<String, Object>) mapJSON.get('updateAuthor'); //get updateAuthor element from json
                String jiraUpdateAuthor;
                if (receivedUpdateAuthor != null){
                    jiraUpdateAuthor = (String)receivedUpdateAuthor.get('displayName');
                }
                updateJIRAComment(jiracommentId, jiraIssueCommentIdRes, jiraCommentObjectId, jiraUpdateAuthor);
            }

            if (actionType == 'UpdateJIRAComment'){
                Case caseIssue = [Select JIRA_Issue_Id__c
                                  From Case
                                  Where Id =: objectId];
                HttpRequest req = buildRequest(baseJIRAUrl, jiraUsername, jiraPassword, objectId, projectKey, issueType, loggedInUser,
                                                 actionType, summary, description, caseIssue.JIRA_Issue_Id__c, jiraComment, jiraCommentId, jiraCommentObjectId);
                system.debug('Request***'+req);
                sendRequest(req);
            }


        } catch(System.CalloutException e) {
            System.debug(e);
        }
    }
 
    // Constructs request needed to create/update a JIRA issue from provided parameters.
    @testVisible private static HttpRequest buildRequest(String baseUrl, String username, String password, String objectId, String projectKey, 
                                                          String issueType, String loggedInUser, String actionType, String summary, String description, 
                                                          String jiraIssueId, String jiraComment, String jiraCommentId, String jiraCommentObjectId) {
        HttpRequest req = new HttpRequest();
        String basicAuthHeader = authHeader(username, password);
        String endpoint = getEndpoint(baseUrl, jiraIssueId, actionType, jiraCommentId);

        // Build JIRA request 
        req.setHeader('Authorization', basicAuthHeader);
        req.setHeader('Content-Type','application/json');
        req.setEndpoint(endpoint);
        system.debug('Endpoint******:'+endpoint);
        if (actionType == 'Create'){
        	req.setMethod('POST');
        	req.setBody('{ \"fields\":{\"project\":{\"key\":\"'+projectKey+'\"},\"summary\": \"'+summary+'\", \"description\": \"'+description+'\", \"issuetype\":{\"name\":\"'+issueType+'\"}, \"customfield_11000\":\"'+loggedInUser+'\", \"customfield_11001\": \"'+objectId+'\"}}');	
        }
        if (actionType == 'Update'){
            req.setMethod('PUT');
        	req.setBody('{ \"fields\":{\"summary\": \"'+summary+'\", \"description\": \"'+description+'\"}}');      
        }
        // Create JIRA Comment
        if (actionType == 'CreateJIRAComment'){
            req.setMethod('POST');
            req.setBody('{ \"body\": \"'+jiraComment+'\"}');    
        }
        // Update JIRA Comment
        if (actionType == 'UpdateJIRAComment'){
            req.setMethod('PUT');
            req.setBody('{ \"body\": \"'+jiraComment+'\"}');      
        }
    
        return req;
    }

    //Update JIRA key on Case based on Salesforce Id
    public static void updateCase(String objectId, String jiraKeyRes, String jiraIssueId){
        Case caseObj = [Select JIRA_Key__c,
                               JIRA_Issue_Id__c,
                               Trigger_Count__c 
                        From Case
                        Where Id =: objectId];

        caseObj.JIRA_Key__c = jiraKeyRes;
        caseObj.JIRA_Issue_Id__c = jiraIssueId;
        if (caseObj.Trigger_Count__c == null || caseObj.Trigger_Count__c == 0){
            caseObj.Trigger_Count__c = 1;
        }else{
            caseObj.Trigger_Count__c = caseObj.Trigger_Count__c + 1;
        }
        
        update caseObj;
    }

    //Update JIRA Issue comment Id on JIRA Comment based on Salesforce Id
    public static void updateJIRAComment(String jiracommentId, String jiraIssueCommentIdRes, String jiraCommentObjectId, 
                                          String jiraUpdateAuthor){
        JIRA_Comment__c[] jiraCommentObj = [Select Comment_Id__c,
                                                    Trigger_Count__c,
                                                    JIRA_User__c
                                              From JIRA_Comment__c
                                              Where Id =: jiraCommentObjectId];

        if (jiraCommentObj != null || jiraCommentObj.size() != 0){
            jiraCommentObj[0].Comment_Id__c = jiraIssueCommentIdRes;
            jiraCommentObj[0].JIRA_User__c = jiraUpdateAuthor;
            
            if (jiraCommentObj[0].Trigger_Count__c == null || jiraCommentObj[0].Trigger_Count__c == 0)
                jiraCommentObj[0].Trigger_Count__c = 1;
            else
                jiraCommentObj[0].Trigger_Count__c = jiraCommentObj[0].Trigger_Count__c + 1;
                
            update jiraCommentObj;
        }
    }

    // Sends a request and returns the response
    public static HttpResponse sendRequest(HttpRequest req) {
        Http http = new Http();
        return http.send(req);
    }

    // Constructs Basic Http Authentication header from provided credentials
    public static String authHeader(String u, String p) {
        Blob headerValue = Blob.valueOf(u + ':' + p);
        return 'Basic ' + EncodingUtil.base64Encode(headerValue);
    }
 
    // Creates the endpoint to create/update the issue from provided parameters.
    private static String getEndpoint(String baseUrl, String jiraIssueId, String actionType, String jiraCommentId) {
    	String completeURL;
        //create issue in JIRA
    	if (actionType == 'Create'){
        	completeURL = baseUrl + '/rest/api/2/issue';
        }
        // update issue in JIRA
        if (actionType == 'Update') {
        	completeURL = baseUrl + '/rest/api/2/issue/' + jiraIssueId;
        }
        // create - update comment in JIRA
        if (actionType == 'CreateJIRAComment'){
            completeURL = baseUrl + '/rest/api/2/issue/' + jiraIssueId + '/comment';
        }
        if(actionType == 'UpdateJIRAComment'){
            completeURL = baseUrl + '/rest/api/2/issue/' + jiraIssueId + '/comment/' + jiraCommentId;
        }
        return completeURL;
        
    }
}