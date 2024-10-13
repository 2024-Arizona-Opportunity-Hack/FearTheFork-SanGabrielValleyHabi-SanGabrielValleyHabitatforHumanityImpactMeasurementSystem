
import { Client, Account } from "appwrite";

const client = new Client();
client
    .setEndpoint('https://cloud.appwrite.io/v1')
    .setProject('670b694d00331959c51e');
const account= new Account(client)

export {account, client};
