xquery version "3.1";

(:~ 
 : eXist-db library module to interact with GitHub via the GitHub API v3 
 :
 : @author Winona Salesky
 : @version 1.0
 : 
 : This code was written by Winona Salesky as part of the Srophé App, a digital humanities application 
 : developed by Syriaca.org: The Syriac Reference Portal and LOGAR: Linked Open Gazetteer of the Andean Region 
 : at Vanderbilt University. Funding was provided by The National Endowment for the Humanities, La Fondazione 
 : Internazionale Premio Balzan, the Trans-Institutional Digital Cultural Heritage Cluster at Vanderbilt University, 
 : and the Center of Digital Humanities Research at Texas A&M University. 
 :
 :)
 
module namespace githubxq="http://exist-db.org/lib/githubxq";
import module namespace crypto="http://expath.org/ns/crypto";
import module namespace http="http://expath.org/ns/http-client";

declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace json = "http://www.json.org";

(:~
 : Send a commit to GitHub. A single file.
 : @param $data object to be commited to GitHub.
 : @param $path to file being commited
 : @param $serialization required if XML.
 : @paran $encoding utf-8|base64
 : @param $branch branch to send commit to. If no branch is specified the default is master.
 : @param $commit-message 
 : @param $repo GitHub repository
 : @param $authorization-token
:)
declare function githubxq:commit($data as item()*, 
    $path as xs:string*, 
    $serialization as xs:string?,
    $encoding as xs:string?,
    $branch as xs:string?, 
    $commit-message as xs:string?, 
    $repo as xs:string,
    $authorization-token as xs:string) as item()* {
(: Step 1. get HEAD SHA and URL for specified branch. If no branch specified use master. :)
    let $branch := if($branch != '') then $branch else 'master'
    let $head :=  
            http:send-request(<http:request http-version="1.1" href="{xs:anyURI(concat($repo,'/git/refs/heads/',$branch))}" method="get">
                                <http:header name="Authorization" value="{concat('token ',$authorization-token)}"/>
                                <http:header name="Connection" value="close"/>
                              </http:request>)
    let $head-data := util:base64-decode($head[2])
    let $head-sha := parse-json($head-data)?object?sha
    let $head-url := parse-json($head-data)?object?url
    return 
       if(starts-with(string($head[1]/@status),'2')) then
(: Step 2. get latest commit to HEAD. Save the commit SHA and URL:)
           let $latest-head-commit := 
                http:send-request(<http:request http-version="1.1" href="{xs:anyURI($head-url)}" method="get">
                                <http:header name="Authorization" value="{concat('token ',$authorization-token)}"/>
                                <http:header name="Connection" value="close"/>
                              </http:request>)
           let $latest-head-commit-data := util:base64-decode($latest-head-commit[2])                              
           let $latest-head-commit-sha := parse-json($latest-head-commit-data)?sha
           let $latest-head-commit-url := parse-json($latest-head-commit-data)?url
           return 
                if(starts-with(string($head[1]/@status),'2')) then
(: Step 3. Post your file to the server. Save the blob SHA:)    
                    let $xml-data := serialize($data,
                                        <output:serialization-parameters>
                                            <output:method>{$serialization}</output:method>
                                        </output:serialization-parameters>) 
                    let $new-blob-content := serialize(
                                        <object>
                                            <content>{$xml-data}</content>
                                            <encoding>{$encoding}</encoding>
                                        </object>, 
                                        <output:serialization-parameters>
                                            <output:method>json</output:method>
                                        </output:serialization-parameters>)                 
                    let $new-blob :=     
                            http:send-request(<http:request http-version="1.1" href="{xs:anyURI(concat($repo,'/git/blobs'))}" method="post">
                                                <http:header name="Authorization" value="{concat('token ',$authorization-token)}"/>
                                                <http:header name="Connection" value="close"/>
                                                <http:header name="Accept" value="application/json"/>
                                                <http:body media-type="application/json" method="text">{$new-blob-content}</http:body>
                                              </http:request>)  
                    let $new-blob-data := util:base64-decode($new-blob[2])                             
                    let $new-blob-sha := parse-json($new-blob-data)?sha        
                    return 
                        if(starts-with(string($new-blob[1]/@status),'2')) then
(: Step 4.  Get commit tree, save tree SHA :)
                            let $commit-tree := 
                                http:send-request(<http:request http-version="1.1" href="{xs:anyURI($latest-head-commit-url)}" method="get">
                                    <http:header name="Authorization" value="{concat('token ',$authorization-token)}"/>
                                    <http:header name="Connection" value="close"/>
                                  </http:request>)
                            let $commit-tree-data := util:base64-decode($latest-head-commit[2])                              
                            let $commit-tree-sha := parse-json($latest-head-commit-data)?object?sha                                  
                            return 
                                if(starts-with(string($commit-tree[1]/@status),'2')) then
(: Step 5. Create a tree containing your new content :)
                                 (: 5. Create a tree containing your new content :)
                                 let $new-tree-content := 
                                     serialize(
                                         <object>
                                             <base_tree>{$latest-head-commit-sha}</base_tree>
                                             <tree json:array="true">
                                                 <path>{$path}</path>
                                                 <mode>100644</mode>
                                                 <type>blob</type>
                                                 <sha>{$new-blob-sha}</sha>
                                             </tree>
                                         </object>, 
                                         <output:serialization-parameters>
                                             <output:method>json</output:method>
                                         </output:serialization-parameters>)
                                 let $new-tree := http:send-request(
                                                     <http:request http-version="1.1" href="{xs:anyURI(concat($repo,'/git/trees'))}" method="post">
                                                         <http:header name="Authorization" value="{concat('token ',$authorization-token)}"/>
                                                         <http:header name="Connection" value="close"/>
                                                         <http:header name="Accept" value="application/json"/>
                                                         <http:body media-type="application/json" method="text">{$new-tree-content}</http:body>
                                                     </http:request>)
                                 let $new-tree-data := util:base64-decode($new-tree[2])                        
                                 let $new-tree-sha := parse-json($new-tree-data)?sha       
                                 return 
                                     if(starts-with(string($new-tree[1]/@status),'2')) then
(: Step 6. Create a new commit with new tree data. Update refs in repository to your new commit SHA:)
                                       let $commit-ref-data :=
                                           serialize(
                                               <object>
                                                   <message>{$commit-message}</message>
                                                   <parents json:array="true">{$latest-head-commit-sha}</parents>
                                                   <tree>{$new-tree-sha}</tree>
                                               </object>, 
                                               <output:serialization-parameters>
                                                   <output:method>json</output:method>
                                               </output:serialization-parameters>)
                                       let $commit :=  http:send-request(
                                                           <http:request http-version="1.1" href="{xs:anyURI(concat($repo,'/git/commits'))}" method="post">
                                                               <http:header name="Authorization" value="{concat('token ',$authorization-token)}"/>
                                                               <http:header name="Connection" value="close"/>
                                                               <http:header name="Accept" value="application/json"/>
                                                               <http:body media-type="application/json" method="text">{$commit-ref-data}</http:body>
                                                           </http:request>)
                                       let $commit-data := util:base64-decode($commit[2])        
                                       let $commit-sha := parse-json($commit-data)?sha        
                                       return 
                                           if(starts-with(string($commit[1]/@status),'2')) then
(: Step 7. Move HEAD reference to new the new commit :)
                                                let $update-ref :=
                                                    serialize(
                                                        <object>
                                                            <sha>{$commit-sha}</sha>
                                                            <force json:literal="true">true</force>
                                                        </object>, 
                                                        <output:serialization-parameters>
                                                            <output:method>json</output:method>
                                                        </output:serialization-parameters>)
                                                let $commit-ref := http:send-request(
                                                                    <http:request http-version="1.1" href="{xs:anyURI(concat($repo,'/git/refs/heads/',$branch))}" method="post">
                                                                        <http:header name="Authorization" value="{concat('token ',$authorization-token)}"/>
                                                                        <http:header name="Connection" value="close"/>
                                                                        <http:header name="Accept" value="application/json"/>
                                                                        <http:body media-type="application/json" method="text">{$update-ref}</http:body>
                                                                     </http:request>)[1]
                                                return 
                                                    if(starts-with(string($commit-ref/@status),'2')) then
                                                        'Success. Your file has been commited to GitHub'
                                                    else ('Failed to move reference:  ',string($commit-ref[1]/@message), util:base64-decode($commit-ref[2]))
(: End step 7 :)
                                           else ('Failed to commit: ',string($commit[1]/@message), ' ', $commit-data)
(: End step 6 :)
                                     else ('Failed to create a new tree: ',string($new-tree[1]/@message), ' ', $new-tree-data)
(: End step 5 :)            
                                else ('Failed to retrieve commit tree: ',string($commit-tree[1]/@message), ' ',  $commit-tree-data)
(: End step 4 :)
                        else ('Failed to store content: ',string($new-blob[1]/@message), ' ', $new-blob-data)
(: End step 3 :)
                else ('Failed to retrieve latest commit for HEAD branch: ',string($latest-head-commit[1]/@message), ' ', $latest-head-commit-data)
(: End step 2 :)
        else ('Failed to retrieve ', $branch ,' branch: ',string($head[1]/@message), ' ', $head-data)
(: End step 1 :)
};

(:~
 : Create a new branch.
 : @param $base branch to use as base to create new branch from, if empty use master
 : @param $branch new branch name
 : @param $repo GitHub repository
 : @param $authorization-token
:)
declare function githubxq:branch($base as xs:string?, 
    $branch as xs:string, 
    $repo as xs:string, 
    $authorization-token as xs:string) as item()* {
(: Step 1. get HEAD SHA and URL for specified branch. If no branch specified use master. :)
    let $base := if($base != '') then $base else 'master'
    let $get-base :=  
            http:send-request(<http:request http-version="1.1" href="{xs:anyURI(concat($repo,'/git/refs/heads/',$base))}" method="get">
                                <http:header name="Authorization" value="{concat('token ',$authorization-token)}"/>
                                <http:header name="Connection" value="close"/>
                              </http:request>)
    let $base-data := util:base64-decode($get-base[2])
    let $base-sha := parse-json($base-data)?object?sha
    let $base-url := parse-json($base-data)?object?url
    return 
       if(starts-with(string($get-base[1]/@status),'2')) then
(: Step 2. create a new branch ref in GitHub:)
            let $new-branch-name := 
                serialize(
                    <object>
                        <ref>refs/heads/{$branch}</ref>
                        <sha>{$base-sha}</sha>
                    </object>, 
                    <output:serialization-parameters>
                        <output:method>json</output:method>
                    </output:serialization-parameters>)            
            let $new-branch := http:send-request(
                                <http:request http-version="1.1" href="{xs:anyURI(concat($repo,'/git/refs'))}" method="post">
                                    <http:header name="Authorization" value="{concat('token ',$authorization-token)}"/>
                                    <http:header name="Connection" value="close"/>
                                    <http:header name="Accept" value="application/json"/>
                                    <http:body media-type="application/json" method="text">{$new-branch-name}</http:body>
                                </http:request>)               
            return 
                if(starts-with(string($new-branch[1]/@status),'2')) then
                    ('Success, you have created a new branch named ',$branch,'.')
                else ('Failed to create new branch:  ',string($new-branch[1]/@message),' ', util:base64-decode($new-branch[2]))
       else ('Failed to retrieve ', $branch ,' branch: ',string($get-base[1]/@message), ' ', $base-data)
};

(:~
 : Create a new pull request.
 : @param $title Title of the pull request
 : @param $body Body of the pull request
 : @param $branch Name of the branch where the changes are
 : @param $base name of the branch you want the changes pulled into 
 : @param $repo GitHub repository
 : @param $authorization-token
:)
declare function githubxq:pull-request($title as xs:string?, 
    $body as xs:string?, 
    $branch as xs:string?, 
    $base as xs:string, 
    $repo as xs:string, 
    $authorization-token as xs:string) as item()* {
    let $pull-request-data :=
                serialize(
                    <object>
                        <title>{$title}</title>
                        <body>{$body}</body>
                        <head>{$branch}</head>
                        <base>{$base}</base>
                    </object>, 
                    <output:serialization-parameters>
                        <output:method>json</output:method>
                    </output:serialization-parameters>)
        let $pull-request := http:send-request(
                                <http:request http-version="1.1" href="{xs:anyURI(concat($repo,'/pulls'))}" method="post">  
                                    <http:header name="Authorization" value="{concat('token ',$authorization-token)}"/>
                                    <http:header name="Connection" value="close"/>
                                    <http:header name="Accept" value="application/json"/>
                                    <http:body media-type="application/json" method="text">{$pull-request-data}</http:body>
                                </http:request>)
        let $pull-request-data := util:base64-decode($pull-request[2])
        return 
            if(starts-with(string($pull-request[1]/@status),'2')) then
                    ('Success, you have created a pull request from ',$branch,' into ', $base,'.')
            else ('Failed to create new pull request:  ',string($pull-request[1]/@message), ' ', $pull-request-data)
};

(:~
 : Respond to GitHub webhook requests. If $branch paramter is used the webhook will respond to requests from 
 : that branch. Otherwise the webhook responds to activity in the master branch.
 : 
 : @param $data content of webhook POST request 
 : @param $application-path Path to eXist-db application 
 : @param $repo GitHub repository
 : @param $branch GitHub branch to get data from
 : @param $key Private key for GitHub authentication 
          https://developer.github.com/webhooks/securing/
 : @param $rateLimitToken Git Token used for rate limiting 
          https://developer.github.com/v3/#rate-limiting
:)
declare function githubxq:execute-webhook($data as item()*, 
    $application-path as xs:string, 
    $repo as xs:string, 
    $branch as xs:string?, 
    $key as xs:string, 
    $rateLimitToken as xs:string?) as item()* {
    if(not(empty($data))) then 
        let $payload := util:base64-decode($data)
        let $json-data := parse-json($payload)
        let $getbranch := if($branch != '') then concat('refs/heads/',$branch) else 'refs/heads/master'
        return
            if($json-data?ref[. = $getbranch]) then 
                 try {
                    if(matches(request:get-header('User-Agent'), '^GitHub-Hookshot/')) then
                        if(request:get-header('X-GitHub-Event') = 'push') then 
                            let $signiture := request:get-header('X-Hub-Signature')
                            let $expected-result := <expected-result>{request:get-header('X-Hub-Signature')}</expected-result>
                            let $actual-result := <actual-result>{crypto:hmac($payload, string($key), "HMAC-SHA-1", "hex")}</actual-result>
                            let $condition := contains(normalize-space($expected-result/text()),normalize-space($actual-result/text()))                	
                            return
                                if ($condition) then 
                                    let $contents-url := substring-before($json-data?repository?contents_url,'{')
                                    return 
                                        try {
                                                (githubxq:do-update(distinct-values($json-data?commits?*?modified?*), $contents-url, $application-path, $repo, $branch,$rateLimitToken),  
                                                githubxq:do-update(distinct-values($json-data?commits?*?added?*), $contents-url, $application-path, $repo, $branch,$rateLimitToken),
                                                githubxq:do-delete(distinct-values($json-data?commits?*?removed?*), $application-path, $repo))
                                        } catch * {
                                        (response:set-status-code( 500 ),
                                            <response status="fail">
                                                <message>Failed to parse JSON {concat($err:code, ": ", $err:description)}</message>
                                            </response>)
                                        }
                			    else 
                			     (response:set-status-code( 401 ),<response status="fail"><message>Invalid secret. </message></response>)
                        else (response:set-status-code( 401 ),<response status="fail"><message>Invalid trigger.</message></response>)
                    else (response:set-status-code( 401 ),<response status="fail"><message>This is not a GitHub request.</message></response>)    
                } catch * {
                    (response:set-status-code( 401 ),
                    <response status="fail">
                        <message>Unacceptable headers {concat($err:code, ": ", $err:description)}</message>
                    </response>)
                }
            else (response:set-status-code( 200 ),<response status="okay"><message>Not from the {$branch} branch.</message></response>)
    else    
            (response:set-status-code( 401 ),
            <response status="fail">
                <message>No post data recieved</message>
            </response>) 
};

(:~  
 : Recursively creates new collections if specified collection does not exist  
 : @param $uri url to resource being added to db 
 :)
declare function githubxq:create-collections($uri as xs:string){
let $collection-uri := substring($uri,1)
for $collections in tokenize($collection-uri, '/')
let $current-path := concat('/',substring-before($collection-uri, $collections),$collections)
let $parent-collection := substring($current-path, 1, string-length($current-path) - string-length(tokenize($current-path, '/')[last()]))
return 
    if (xmldb:collection-available($current-path)) then ()
    else xmldb:create-collection($parent-collection, $collections)
};

(:~  
 : Get file information for file in commit. 
 : @param $file-path internal GitHub path, sent by webhook
 : @param $commits serilized json data
 : @param $contents-url string pointing to resource on github
 : @param $application-path Path to eXist-db application 
 : @param $repo GitHub repository
 : @param $branch GitHub branch to get data from
 : @param $rateLimitToken GitHub rateLimit token
 :)
declare function githubxq:get-file-data($file-path as xs:string, $contents-url as xs:string, $branch,$rateLimitToken){       
let $branch := if($branch != '') then concat('/',$branch)  else '/master'
let $raw-url := concat(replace(replace($contents-url,'https://api.github.com/repos/','https://raw.githubusercontent.com/'),'/contents/',''),$branch,'/',$file-path)            
return 
      http:send-request(<http:request http-version="1.1" href="{xs:anyURI($raw-url)}" method="get">
                            {if($rateLimitToken != '') then
                                <http:header name="Authorization" value="{concat('token ',$rateLimitToken)}"/>
                            else() }
                            <http:header name="Connection" value="close"/>
                        </http:request>)[2]                      
};

(:~
 : Updates files in eXist-db with GitHub version of the file.
 : Ignores .xar files. 
 : @param $commits serilized json data
 : @param $contents-url string pointing to resource on github
 : @param $application-path Path to eXist-db application 
 : @param $repo GitHub repository
 : @param $branch GitHub branch to get data from
 : @param $rateLimitToken GitHub rateLimit token
:)
declare function githubxq:do-update($commits as xs:string*, $contents-url as xs:string?, $application-path, $repo, $branch,$rateLimitToken){
    for $file in $commits
    let $file-name := tokenize($file,'/')[last()]
    let $file-data := 
        if(contains($file-name,'.xar')) then ()
        else githubxq:get-file-data($file, $contents-url, $branch,$rateLimitToken)
    let $resource-path := substring-before(replace($file,$repo,''),$file-name)
    let $exist-collection-url := xs:anyURI(replace(concat($application-path,'/',$resource-path),'/$',''))        
    return 
        try {
             if(contains($file-name,'.xar')) then ()
             else if(xmldb:collection-available($exist-collection-url)) then 
                <response status="okay">
                    <message>{xmldb:store($exist-collection-url, xmldb:encode-uri($file-name), $file-data)}</message>
                </response>
             else
                <response status="okay">
                    {(githubxq:create-collections($exist-collection-url),xmldb:store($exist-collection-url, xmldb:encode-uri($file-name), $file-data))}
               </response>  
        } catch * {
        (response:set-status-code( 500 ),
            <response status="fail">
                <message>Failed to update resource {xs:anyURI(concat($exist-collection-url,'/',$file-name))}: {concat($err:code, ": ", $err:description)}</message>
            </response>)
        }
};

(:~
 : Removes files from the database uses xmldb:remove.
 : @param $commits serilized json data
 : @param $application-path Path to eXist-db application 
 : @param $repo GitHub repository
:)
declare function githubxq:do-delete($commits as xs:string*, $application-path as xs:string, $repo as xs:string){
    for $file in $commits
    let $file-name := tokenize($file,'/')[last()]
    let $resource-path := substring-before(replace($file,$repo,''),$file-name)
    let $exist-collection-url := xs:anyURI(replace(concat($application-path,'/',$resource-path),'/$',''))
    return
        if(contains($file-name,'.xar')) then ()
        else 
            try {
                <response status="okay">
                    <message>{xmldb:remove($exist-collection-url, $file-name)}</message>
                </response>
            } catch * {
            (response:set-status-code( 500 ),
                <response status="fail">
                    <message>Failed to remove resource {xs:anyURI(concat($exist-collection-url,'/',$file-name))}: {concat($err:code, ": ", $err:description)}</message>
                </response>)
            }
};