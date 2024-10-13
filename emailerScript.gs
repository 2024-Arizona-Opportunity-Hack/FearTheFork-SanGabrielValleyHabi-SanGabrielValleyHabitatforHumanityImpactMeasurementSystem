function sendFormEmails() {
  // Open the active spreadsheet
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
  var lastRow = sheet.getLastRow(); // Get the last row number
  var data = sheet.getRange(lastRow, 1, 1, sheet.getLastColumn()).getValues(); // Get the data from the last row
  
  // Define the form links associated with each form type
  var formLinks = {
    "hppExitSurvey": "https://docs.google.com/forms/d/e/1FAIpQLSfVakwoQ0sRJ0ia1RTOVPCCNs1QIuFNgCdylQW9SQGC5-yyMw/viewform?usp=sf_link",
    "surveyQ1": "https://docs.google.com/forms/d/e/1FAIpQLScu5qKy5LHvIgi1fVNC3K7Y7FTdYOdVvRkl4PAfV36vwoDX_w/viewform?usp=sf_link",
    "surveyQ2": "https://docs.google.com/forms/d/e/1FAIpQLSeVYZ8mnzosiI_bVLLALZPdB7UedV-pSreL62PpzYc0bK7SFQ/viewform?usp=sf_link",
    // Add more forms as needed
  };

  var email = data[0][0];      // Email is in the first column
  var formType = data[0][1];   // Form type is in the second column

  // Check if the form type exists in the formLinks dictionary
  if (formLinks[formType]) {
    var formLink = formLinks[formType];
    var subject = 'Please fill out the ' + formType;
    var message = 'Hello,\n\nPlease complete the following form: ' + formLink + '\n\nThank you!';
    
    // Send the email
    MailApp.sendEmail(email, subject, message);
  } else {
    Logger.log('Form type "' + formType + '" not found for email: ' + email);
  }
}