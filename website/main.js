import './style.css'
import { account} from './appwrite'

const loginBtn = document.getElementById('login-btn')
const logoutBtn = document.getElementById('logout-btn')
const profileScreen= document.getElementById('profile-screen')
const loginScreen= document.getElementById('login-screen')

async function handleLogin(){
    account.createOAuth2Session(
        'google',
        'http://127.0.0.1:5500/',
        'http://127.0.0.1:5500/'
    )
}

async function getUser(){
    try{
        const user=await account.get()
        renderProfileScreen(user)
    }catch(error){
        renderLoginScreen()
    }
}

function renderLoginSCreen (){
    loginScreen.classList.remove('hidden')
}

async function renderProfileScreen(user){
    document.getElementById('user-name').textContent = user.name

    profileScreen.classList.remove('hidden')
}