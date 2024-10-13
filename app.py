from flask import Flask, request, session
from twilio.twiml.messaging_response import MessagingResponse
from twilio.rest import Client
import os
import google.auth
from googleapiclient.discovery import build
from google.oauth2.service_account import Credentials
import logging

app = Flask(__name__)
# Replace the below string with your own secret key for session management
app.secret_key = 'vujQXnZ6KpWTYHFaL639RKqhuQhqFLp+Q3ZZaR23yws='  # **Replace with your secure secret key**

# -----------------------------------
# Twilio Configuration
# -----------------------------------
# Replace these placeholder strings with your actual Twilio Account SID and Auth Token
TWILIO_ACCOUNT_SID = 'AC0d6dc0a9f82dda1dd7a80fcbce2777cc'  # **Replace with your Twilio Account SID**
TWILIO_AUTH_TOKEN = 'b5bd66f90d59c3f09c28b011f1a54327'    # **Replace with your Twilio Auth Token**
TWILIO_NUMBER = '+18447934743'                 # **Replace with your Twilio phone number**

# Initialize Twilio Client
twilio_client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)

# -----------------------------------
# Google Sheets Configuration
# -----------------------------------
# Replace with the path to your downloaded Google Service Account JSON key file
SERVICE_ACCOUNT_FILE = '/Users/mannanxanand/OHacks/ohacks-fear-the-fork-3b49ec5fa8ac.json'  # **Ensure correct path and remove trailing dot if present**
SCOPES = ['https://www.googleapis.com/auth/spreadsheets']
SPREADSHEET_ID = '1YUI7qdNovLNbjkfMamYkhh1JvYiCARYtpRqBgygJskA'  # **Replace with your Google Spreadsheet ID**

# Initialize Google Sheets API client
credentials = Credentials.from_service_account_file(
    SERVICE_ACCOUNT_FILE, scopes=SCOPES)
service = build('sheets', 'v4', credentials=credentials)

# -----------------------------------
# Logging Configuration
# -----------------------------------
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# -----------------------------------
# Survey Configuration
# -----------------------------------
survey_questions = [
    "Do you consent to participate in this survey? (Yes/No)",
    "Please provide your full name:",
    "Street Address:",
    "Unit/Apt. #:",
    "City (e.g., Alhambra, Altadena, ...):",
    "Best Phone Number:",
    "Email Address:",
    "How did you hear about our program?",
    "Are you the only person on the title? (Yes/No)",
    "What year did you purchase your home?",
    "Has your home ever been retrofitted? (Yes/No)",
    "How many people live in your home? (1-5, More Than 5)",
    "Approximate annual household income?",
    "Are you currently unemployed? (Yes/No)",
    "Is there someone else in your household who will be acting as the main point of contact? (Yes/No)",
    "If yes, please list that contact person’s full name and relationship to you.",
    "Contact's best phone number:",
    "Contact's email address:",
    "Please share any additional information about your repair request or situation you feel would be relevant."
]

# -----------------------------------
# Helper Functions
# -----------------------------------

def send_sms(to_number, body_message):
    """
    Sends an SMS message using Twilio's REST API.
    
    Args:
        to_number (str): Recipient's phone number in E.164 format.
        body_message (str): The content of the SMS message.
    """
    try:
        message = twilio_client.messages.create(
            body=body_message,
            from_=TWILIO_NUMBER,
            to=to_number
        )
        logger.info(f"Message sent to {to_number}: SID {message.sid}")
    except Exception as e:
        logger.error(f"Failed to send message to {to_number}: {e}")

def validate_input(question_number, input_text):
    """
    Validates user input based on the current question number.
    
    Args:
        question_number (int): The index of the current question.
        input_text (str): The user's response.
    
    Returns:
        bool: True if input is valid, False otherwise.
    """
    if question_number == 0:
        return input_text.lower() in ['yes', 'no']
    elif question_number == 1:
        return len(input_text.strip()) > 0  # Full Name
    elif question_number == 2:
        return len(input_text.strip()) > 0  # Street Address
    elif question_number == 3:
        return len(input_text.strip()) > 0  # Unit/Apt. #
    elif question_number == 4:
        cities = [
            "Alhambra", "Altadena", "Arcadia", "Atwater", "Azusa",
            "Baldwin Park", "Bradbury", "Duarte", "Eagle Rock",
            "El Monte", "South El Monte", "Glendale", "El Sereno",
            "Highland Park", "Irwindale", "La Canada", "La Crescenta",
            "Monrovia", "Lincoln Heights", "Monterey Hills",
            "Monterey Park", "Montrose", "Pasadena", "South Pasadena",
            "Rosemead", "San Gabriel", "San Marino", "Sierra Madre",
            "Sunland", "Temple City", "Tujunga", "Other"
        ]
        return input_text in cities
    elif question_number == 5:
        return input_text.isdigit() and len(input_text) >= 10  # Best Phone Number
    elif question_number == 6:
        return "@" in input_text and "." in input_text  # Email Address
    elif question_number == 7:
        return len(input_text.strip()) > 0  # How did you hear about our program?
    elif question_number == 8:
        return input_text.lower() in ['yes', 'no']  # Only person on title
    elif question_number == 9:
        return input_text.isdigit() and 1900 <= int(input_text) <= 2100  # Year purchased
    elif question_number == 10:
        return input_text.lower() in ['yes', 'no']  # Retrofitted
    elif question_number == 11:
        options = ["1", "2", "3", "4", "5", "More Than 5"]
        return input_text in options
    elif question_number == 12:
        incomes = [
            "Less than $66,000",
            "$66,000 - $77,700",
            "$77,770 - $88,800",
            "$88,800 - $99,900",
            "$99,900 - $110,950",
            "$110,950 - $119,850",
            "More than $119,850"
        ]
        return input_text in incomes
    elif question_number == 13:
        return input_text.lower() in ['yes', 'no']  # Currently unemployed
    elif question_number == 14:
        return input_text.lower() in ['yes', 'no']  # Main point of contact
    elif question_number == 15:
        return len(input_text.strip()) > 0  # Contact's full name and relationship
    elif question_number == 16:
        return input_text.isdigit() and len(input_text) >= 10  # Contact's phone number
    elif question_number == 17:
        return "@" in input_text and "." in input_text  # Contact's email address
    elif question_number == 18:
        return True  # Additional information is optional
    else:
        return False  # Undefined question number

def save_to_sheet(sender, responses):
    """
    Appends survey responses to the Google Sheet.
    
    Args:
        sender (str): The phone number of the user.
        responses (list): List of responses collected from the user.
    """
    try:
        sheet = service.spreadsheets()
        # Prepend the sender's number to responses for identification
        values = [[sender] + responses]
        body = {
            'values': values
        }
        sheet.values().append(
            spreadsheetId=SPREADSHEET_ID,
            range='Sheet1!A1',  # Ensure that headers are in the first row
            valueInputOption='RAW',
            body=body
        ).execute()
        logger.info(f"Responses from {sender} saved to sheet.")
    except Exception as e:
        logger.error(f"Failed to save responses from {sender}: {e}")

# -----------------------------------
# Flask Routes
# -----------------------------------

@app.route('/sms', methods=['POST'])
def sms_reply():
    """
    Handles incoming SMS messages from Twilio.
    Manages the survey flow based on user responses.
    """
    msg = request.form.get('Body').strip()
    sender = request.form.get('From')

    if not sender:
        logger.warning("No sender information found in the request.")
        return "Invalid request.", 400

    if sender not in session:
        session[sender] = {'responses': [], 'current_question': 0}
        logger.info(f"New session started for {sender}.")

    user_session = session[sender]
    resp = MessagingResponse()

    current_q = user_session['current_question']

    if current_q < len(survey_questions):
        if current_q == 0:
            # Consent Handling
            if msg.lower() == 'yes':
                user_session['responses'].append(msg)
                user_session['current_question'] += 1
                next_question = survey_questions[user_session['current_question']]
                resp.message(next_question)
                logger.info(f"{sender} consented to participate. Moving to question {user_session['current_question'] + 1}.")
            elif msg.lower() == 'no':
                resp.message("You have opted out of the survey. Thank you.")
                session.pop(sender, None)
                logger.info(f"{sender} declined to participate in the survey.")
            else:
                resp.message("Please respond with Yes or No to consent.")
                logger.warning(f"{sender} provided invalid consent response: {msg}")
        else:
            # Validate user response
            is_valid = validate_input(current_q, msg)
            if is_valid:
                user_session['responses'].append(msg)
                logger.info(f"Received valid response from {sender} for question {current_q + 1}.")
                if current_q + 1 < len(survey_questions):
                    user_session['current_question'] += 1
                    next_question = survey_questions[user_session['current_question']]
                    resp.message(next_question)
                else:
                    # Survey Completed
                    save_to_sheet(sender, user_session['responses'])
                    resp.message("Thank you for completing the survey!")
                    session.pop(sender, None)
                    logger.info(f"Survey completed by {sender}.")
            else:
                resp.message("Invalid input. Please try again.")
                logger.warning(f"Invalid response from {sender} for question {current_q + 1}: {msg}")
    else:
        # This should not happen; reset session
        resp.message("An error occurred. Please start the survey again.")
        session.pop(sender, None)
        logger.error(f"Session out of bounds for {sender}.")

    return str(resp)

@app.route('/start_survey', methods=['POST'])
def start_survey():
    """
    Initiates the survey by sending the first question to the specified phone number.
    Expects a POST request with a 'to' parameter containing the recipient's phone number.
    """
    to_number = request.form.get('to')
    if not to_number:
        logger.error("No 'to' parameter provided in /start_survey request.")
        return "Missing 'to' parameter.", 400

    initial_message = survey_questions[0]  # "Do you consent to participate in this survey? (Yes/No)"
    send_sms(to_number, initial_message)
    logger.info(f"Survey initiation message sent to {to_number}.")

    return "Survey initiation SMS sent.", 200

# -----------------------------------
# Running the Flask Application
# -----------------------------------

if __name__ == '__main__':
    # Enable debug mode for development (disable in production)
    app.run(debug=True)