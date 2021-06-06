const http = require('https');
const fs = require('fs');
const readline = require('readline');
const {google} = require('googleapis');
const googleAuth = require('google-auth-library');
const yaml = require('js-yaml');

const SCOPES = ['https://www.googleapis.com/auth/calendar'];
const TOKEN_DIR = (process.env.HOME || process.env.HOMEPATH ||
    process.env.USERPROFILE) + '/.gcal-credentials/';
const TOKEN_PATH = TOKEN_DIR + 'lb-calendar-sync.json';

const calendar = google.calendar('v3');

let calendarId;
let workCalApi;
let workEmail;
let calQuery;

function authorize(credentials, callback) {
  let clientSecret = credentials.installed.client_secret;
  let clientId = credentials.installed.client_id;
  let redirectUrl = credentials.installed.redirect_uris[0];
  let OAuth2 = google.auth.OAuth2;
  let oauth2Client = new OAuth2(clientId, clientSecret, redirectUrl);
  // Check if previously stored token.
  fs.readFile(TOKEN_PATH, (err, token) => {
    if (err) {
      getNewToken(oauth2Client, callback);
    } else {
      oauth2Client.credentials = JSON.parse(token);
      google.options({auth:oauth2Client});
      callback();
    }
  });
}

function getNewToken(oauth2Client, callback) {
  var authUrl = oauth2Client.generateAuthUrl({
    access_type: 'offline',
    scope: SCOPES
  });
  console.log('Authorize this app by visiting this url: ', authUrl);
  var rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });
  rl.question('Enter the code from that page here: ', (code) => {
    rl.close();
    oauth2Client.getToken(code, (err, token) => {
      if (err) {
        console.log('Error while trying to retrieve access token', err);
        return;
      }
      oauth2Client.credentials = token;
      storeToken(token);
      google.options({auth: oauth2Client});
      callback();
    });
  });
}

function storeToken(token) {
  try {
    fs.mkdirSync(TOKEN_DIR);
  } catch (err) {
    if (err.code != 'EEXIST') {
      throw err;
    }
  }
  fs.writeFile(TOKEN_PATH, JSON.stringify(token));
  console.log('Token stored to ' + TOKEN_PATH);
}

async function getOldGCalEvents () {
  let options = {
    calendarId: 'primary',
    // timeMin: (new Date()).toISOString(),
    singleEvents: true,
    orderBy: 'startTime',
    q: calQuery
  };
  console.log('> Getting Old Events');
  let response = await calendar.events.list(options);
  let events = response.data.items;
  
  if (events.length != 0) {
    console.log('> Deleting Old Events');
    let tasks = [];
    for (let i = 0; i < events.length; i++) {
      let event = events[i];
      await deleteGCalEvent(event.id);    
    }
  } 
  getWorkEvents();

}

async function deleteGCalEvent (eventId,callback) {
  let options = {
    calendarId: 'primary',
    eventId: eventId
  };
  return await calendar.events.delete(options);
}

async function getWorkEvents () {
  let email = workEmail;
  var options = {
    host: workCalHost,
    path: `${workCalApi}${email}`
  };
  http.get(options, (res) => {
    let str = '';
    res.on('data', (chunk) => {
      str += chunk;
    });
    res.on('end', () => {
      let lbData = JSON.parse(str);
      console.log('> Getting Work Events');
      createGCalEvents(lbData);
    });
  });
}

async function createGCalEvents (data) {
  console.log('> Creating Events')
  let events = [];

  for (let i = 0; i < data.length; i++) {

    let startDate;
    let endDate;
    let start;
    let end;

    let eventData = {
      summary: eventFormat(data[i]),
      description: calQuery,
      reminders: {
        'useDefault': false
      }
    }

    if (data[i].custom_dates) {

      data[i].custom_dates.forEach(date => {
        let event = {...eventData}
        event['start'] = {
          dateTime: new Date(date.start),
          timeZone: data[i].timezone
        }
        event['end'] = {
          dateTime: new  Date(date.end),
          timeZone: data[i].timezone
        }

        events.push(event)

      });



    } else {
      startDate = new Date(data[i].start);
      endDate = new Date(data[i].end);
      endDate.setDate(endDate.getDate()+1);
      start = startDate.toISOString().split('T')[0]
      end = endDate.toISOString().split('T')[0]

      let event = {...eventData}
      event['start'] = {date: start}
      event['end'] = {date: end}

      events.push(event)
    }

  }
  for (e of events) {
    // console.log(e)
    await calendar.events.insert({
      calendarId: 'primary',
      resource: e
    });
  }
}

function eventFormat(sch) {
  let count = sch['cnt'];
  let courseTitle = sch['gcal_title'].split(' - ');
  let newTitle = '';
  if (sch['custom_name'] != '') {
    newTitle = `[${count}] ${sch['custom_name']}`;
  } else {
    newTitle = `[${count}] ${courseTitle[0]}`;
  }
  newTitle = `${newTitle} : ${sch['loc']}`;
  return newTitle;
}

fs.readFile('client_secret.json', (err, content) => {
  if (err) {
    console.log('Error loading client secret file: ' + err);
    return;
  }

  let config = yaml.load(fs.readFileSync('config.yaml', 'utf8'));
  workCalHost = config.workCalHost;
  workCalApi = config.workCalApi;
  workEmail = config.workEmail;
  calQuery = config.calQuery;

  authorize(JSON.parse(content), getOldGCalEvents);
});
