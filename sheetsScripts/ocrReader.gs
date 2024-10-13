//helper function for getting drive links formatted properly
function convertGoogleDriveLink(originalLink) {
  var fileIdMatch = originalLink.match(/id=([^&]+)/);
  if (!fileIdMatch) {
    fileIdMatch = originalLink.match(/\/d\/([^\/]+)/);
  }
  
  if (fileIdMatch && fileIdMatch[1]) {
    var fileId = fileIdMatch[1];
    return "https://drive.google.com/uc?export=view&id=" + fileId;
  } else {
    return "Invalid Google Drive link format";
  }
}

//add new data to excel sheet
function processNewData(e) {
  var totalAnaswered = 0;
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();

  //this would normally be hidden
  var apiKey = 'redacted';
  //gpt prompt
  var prompt = "You are provided with an image of a quiz that contains multiple-choice/select questions. Please extract only the answers that are visibly marked by the user. Do not include unselected options at all. Provide the output in array where each answer is a different element of the array. Do not include any additional words or formatting, only the selected answers in the order they appear in the quiz.";

  //starting url
  var url = 'https://api.openai.com/v1/chat/completions';

  var lastRow = sheet.getLastRow();
  var saveCol = 11; // Starting column for info we fill

  //loop thru each drive link we do have
  for(var i = 2; i < 10; i++) {
    var value = sheet.getRange(lastRow, i).getValue();
    //convert to proper links
    var convertedValue = convertGoogleDriveLink(value);
    Logger.log(convertedValue);

    // Prepare GPT request
    var payload = {
    model: "gpt-4o-mini",
    messages: [
      {
        role: "user",
        content: [
          { type: "text", text: prompt },
          {
            type: "image_url",
            image_url: { url: convertedValue }
          }
        ]
      }
    ],
    max_tokens: 300

    };

    var options = {
      method: 'post',
      contentType: 'application/json',
      headers: {
        'Authorization': 'Bearer ' + apiKey
      },
      payload: JSON.stringify(payload)
    };

    //send to gpt
    try {
      var response = UrlFetchApp.fetch(url, options);
      var json = JSON.parse(response.getContentText());
      Logger.log(response);
      Logger.log(json);

      // Get the content and trim any whitespace
      var t = json.choices[0].message.content.trim();
      Logger.log("Raw GPT response: " + t);

      // Clean up the response
      t = t.replace(/[\[\]"]+/g, '');

      // Split the response into an array of answers
      var answers = t.split(',').map(function(answer) {
        return answer.trim(); // Trim whitespace from each answer
      });

      // Write each answer to its respective column
      for (var j = 0; j < answers.length; j++) {
        sheet.getRange(lastRow, saveCol + totalAnaswered).setValue(answers[j]);
        totalAnaswered++;
      }
    } catch (error) {
      Logger.log('Error: ' + error);
    }
  }
}