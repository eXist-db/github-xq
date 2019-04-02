
# GitHub API XQuery Library
The GitHub API XQuery Library provides XQuery functions for interacting with the GitHub API (version 3.0). 
This library currently supports the following interactions with GitHub: 
* Create a new branch
* Commit files to a branch
* Submit a pull request
* Respond to GitHub webhooks 

This code was written by Winona Salesky as part of the Srophé App, a digital humanities application 
developed by Syriaca.org: The Syriac Reference Portal [http://syriaca.org/] and LOGAR: Linked Open Gazetteer of the 
Andean Region [http://logarandes.org/] at Vanderbilt University. Funding was provided by The National Endowment for the Humanities, 
La Fondazione Internazionale Premio Balzan, the Trans-Institutional Digital Cultural Heritage Cluster at Vanderbilt University, 
and the Center of Digital Humanities Research at Texas A&M University. 
 
## Requirements
* eXist-db 3.x.x or higher
* EXPath Cryptographic Module Implementation [http://expath.org/ns/crypto]
* EXPath HTTP Client [http://expath.org/ns/http-client]

## Installation
The package can be installed via the eXist-db package manager. 

## Available Functions

### branch 
Create a new branch on GitHub

```
githubxq:branch($base as xs:string?, 
    $branch as xs:string, 
    $repo as xs:string, 
    $authorization-token as xs:string)
```    

Parameters:
 * $base - The branch to use as base to create new branch from, if empty use master
 * $branch - New branch name
 * $repo - Full path to the GitHub repository
 * $authorization-token - Your personal authorization token. (See: GitHub documentation on authorization tokens [https://github.com/blog/1509-personal-api-tokens])
Returns:
 * item()*

Example:
``` 
githubxq:branch('master', 
    'newBranchName', 
    'https://api.github.com/repos/wsalesky/blogs', 
    'AUTHORIZATION-TOKEN')
```
  
### commit 
Send a commit to GitHub. *A single file.
```
githubxq:commit($data as item()*, 
    $path as xs:string*, 
    $serialization as xs:string?,
    $encoding as xs:string?,
    $branch as xs:string?, 
    $commit-message as xs:string?, 
    $repo as xs:string,
    $authorization-token as xs:string)
```

Parameters:
* $data - Object/file to be committed to GitHub.
* $path - Path to file being committed.  Path must be relative to GitHub repository root, should not start with a slash.
* $serialization - *Not sure this is necessary
* $encoding - utf-8|base64
* $branch - Branch to send commit to. If no branch is specified the default is master.
* $commit-message - Commit message.
* $repo - Full path to the GitHub repository
* $authorization-token - Your personal authorization token.
Returns:
 * item()*
 
Example:
 ```
let $data1 := doc('/db/apps/ba-data/data/bibl/tei/2G3TK7GI.xml')
return 
    githubxq:commit($data1, 
        '/db/apps/ba-data/data/bibl/tei/2G3TK7GI.xml', 
        'xml',
        'utf-8',
        'newBranchName',
        'Add new file to newBranchName',
        'https://api.github.com/repos/wsalesky/blogs',
        'AUTHORIZATION-TOKEN') 
 ```
 
### Pull request 
Create a new pull request.

```
githubxq:pull-request($title as xs:string?, 
    $body as xs:string?, 
    $branch as xs:string?, 
    $base as xs:string, 
    $repo as xs:string, 
    $authorization-token as xs:string)
```
    
Parameters:
* $title - Title of the pull request
* $body - Body/message of the pull request
* $branch - Name of the branch where the changes are
* $base - Name of the branch you want the changes pulled into 
* $repo - GitHub repository
* $authorization-token - Your personal authorization token.

Example: 
```
githubxq:pull-request('Merge newBranchName', 
    'Merge changes made to newBranchName into the master branch', 
    'master', 
    'newBranchName', 
    'https://api.github.com/repos/wsalesky/blogs', 
    'AUTHORIZATION-TOKEN')
```

### GitHub webhooks
Respond to GitHub webhook requests. Use this function to create an endpoint to respond to GitHub webhook requests. 
The script evaluates the request and takes appropriate action based on the contents of the request; uploads new files, updates existing files or deleting files.
This can be a useful method of keeping your eXist-db up to date with edits happening on GitHub, a common workflow for distributed teams 
of developers. If the `$branch` parameter is used the webhook will respond to requests from the named branch, otherwise the webhook 
responds to activity in the master branch. 

```
githubxq:execute-webhook($data as item()*, 
    $application-path as xs:string, 
    $repo as xs:string, 
    $branch as xs:string?, 
    $key as xs:string, 
    $rateLimitToken as xs:string?)
```

Parameters:
* $data - Content of webhook POST request 
* $application-path - Path to eXist-db application 
* $repo - Path to GitHub repository
* $branch - GitHub branch to get data from
* $key - Private key for GitHub authentication 
**          https://developer.github.com/webhooks/securing/
* $rateLimitToken -  Git Token used for rate limiting. This is optional. 
GitHub restricts wehhook activity to 60 unauthenticated requests per hour. 
**         https://developer.github.com/v3/#rate-limiting

Example: 
```
let $data := request:get-data()
return 
    githubxq:execute-webhook($data, 
        '/db/apps/ba-data',  
        'https://github.com/wsalesky/blogs/', 
        'OPTIONAL-BRANCH', 
        'YOUR-SECRET-KEYE', 
        'OPTIONAL-RATE-LIMIT-KEY')
```

Note: The XQuery responding to GitHub must be run with elevated privileges in order to save and edit the files in your application. 

Example: ` sm:chmod(xs:anyURI(xs:anyURI('YOUR-ENDPOINT.xql'), "rwsr-xr-x")) `

### Set up GitHub webhooks
Read about webhooks here: [https://developer.github.com/webhooks/]

Webhook settings: 

* Payload URL:  Full url to your endpoint. (example: http://5ba09277.ngrok.com/exist/apps/srophe/modules/git-sync.xql)
* Content type: application/json
* Secret: You will need to generate a secret key to verify webhook requests. See: https://developer.github.com/webhooks/securing/
Keep track of the secret, as it will have to be added the access-config.xml file, which is not stored in the github repository. 
* Leave all the other default options checked

