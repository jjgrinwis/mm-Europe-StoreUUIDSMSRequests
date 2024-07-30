@App:name("StoreUUIDSMSRequests")
@App:qlVersion("2")

/**
    This endpoint should receive messages when the following verification endpoints are called:
    - https://docs.nextreason.com/reference/unify-journeys-api-resend-verification
    - https://docs.nextreason.com/reference/sendotp-1
    
    With both calls, the auth_type defines the payload of the user_id which can be an email address or email.
    In our EdgeWorker code we will be adding two fields, the user_id_sha and url_path json payload:
    
    {
      "auth_type": "sms",
      "client_id": "123",
      "redirect_uri": "https://redirect_url",
      "user_id": "0612345678",
      "user_id_sha":"c0b290ded1e79a3e7b7c61e2ab6fe4e4184f854ef755f064d4e8903f7d2ee474",
      "url_path": "/idp/1/otp/send"
    }
    
    The user_id will be used to lookup the UUID which will also be our _key. We can drop the user_id(mobilenumber) for privacy reasons.
    We will only store the sha256 of the user_id. As we can't create a sha digest in the stream worker, let's do that in the EdgeWorker.

    If input is already providing a 'valid' uuid, skip the whole lookup part and just write data to sink which will start the query worker.
    Some endpoints don't provide a user_id like: https://docs.nextreason.com/reference/unify-journeys-api-change-id
    But it should have a valid token. EdgeWorker should get the sub out of the token and feed it into our stream worker.

    Our final collection will contain something like this where the _key is UUID of this user which will match to the identity cloud backend.
    {
      "fraudHits": [
        {
          "time": 1720033142171,
          "user_id": "53af329367f2bd21cf89bf1c2e5c78c73e63593a62ce5aa926a5ef770fda4026",
          "url_path": "/test/send/nora"
        },
        {
          "time": 1720033143607,
          "user_id": "53af329367f2bd21cf89bf1c2e5c78c73e63593a62ce5aa926a5ef770fda4026",
          "url_path": "/test/send/nora"
        }
      ],
      "fraudster": false
    }
    
    An external service can now decide when something is fraud and test the fraudster boolean.
**/

-- Defines `VerificationCallHTTPSource` stream to process events having an auth_type and user_id
-- we're only interested in a couple of fields, ignoring the other fields in the json payload.
-- CREATE STREAM VerificationCallSource (auth_type string, user_id string, user_id_sha string, url_path string);
-- uuid might be there, it's optional 
CREATE SOURCE VerificationCallHTTPSource WITH (type = 'http', map.type='json') (auth_type string, user_id string, user_id_sha string, url_path string, uuid string);

-- Define a sink to publish the data to the external application.
-- For now just using some dummy endpoint to create a uuid, this should be the identity cloud profile lookup page
-- https://techdocs.akamai.com/identity-cloud/docs/view-a-user-profile
CREATE SINK GetUUIDFromAIC WITH (type='http-call', publisher.url='https://api.grinwis.com/uuid/', method='POST', headers="'Content-Type:application/json'", sink.id="getUUID",map.type='json', map.payload="""{"user_id":"{{user_id}}"}""") (user_id STRING, time long, user_id_sha STRING, url_path string);

-- The results from our HTTP call should be available in this response body. 
-- It will contain a json body like {"uuid":"12345"}. So let's get that uuid.
-- Our input vars are available via trp:<attribute name> so let's map them into our object as we can't point back to our input stream.
CREATE SOURCE UUIDInfo WITH (type='http-call-response', sink.id='getUUID', map.type='json', 
map.attributes.uuid = '$.uuid',
map.attributes.user_id = 'trp:user_id_sha',
map.attributes.url_path = 'trp:url_path',
map.attributes.time = 'trp:time') (uuid string, user_id string, url_path string, time long);

-- We've reached the end of our stream, just feed this info into our query worker which will store the data.
-- We don't care about the results but could forward the results into some other output
CREATE SINK UpdateFraudWorkerStream WITH (type='query-worker', query.worker.name="updateFraud") (key string, fraud object );

-- Let's lookup the UUID attached to this user by sending it into http sink doing the lookup.
-- we can ignore any payload where the auth_type is not sms.
@info(name = 'lookup-uuid')
INSERT INTO GetUUIDFromAIC
SELECT user_id, time:timestampInMilliseconds() AS time, user_id_sha, url_path
FROM VerificationCallHTTPSource[auth_type == 'sms' AND uuid is null];

-- If we have a UUID with the correct format (8-4-4-4-12), just skip the lookup of the uuid
-- we can ignore any payload where the auth_type is not sms.
@info(name = 'skip-lookup-uuid')
INSERT INTO UpdateFraudWorkerStream
SELECT uuid as key, json:toObject(str:fillTemplate("""{"time": {{1}}, "user_id": "{{2}}", "url_path": "{{3}}"}""", time:timestampInMilliseconds(), user_id, url_path)) AS fraud
FROM VerificationCallHTTPSource[auth_type == 'sms' AND regex:matches('^[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}$', uuid)];

-- Let's first create some nice json string via fillTemplate and convert json string to an object.
-- don't forget to add some "" for fields that are strings!
@info(name = 'create-json-object')
INSERT INTO UpdateFraudWorkerStream
SELECT uuid as key, json:toObject(str:fillTemplate("""{"time": {{1}}, "user_id": "{{2}}", "url_path": "{{3}}"}""", time, user_id, url_path)) AS fraud
FROM UUIDInfo;
