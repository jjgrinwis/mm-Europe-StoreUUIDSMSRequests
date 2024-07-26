/*
Our Macrometa EdgeWorker script to fire off requests to stream worker.
This is a modified version as we're going to use typescript and POST
*/
import { createResponse } from "create-response";
import { TextEncoder } from "encoding";
import { crypto } from "crypto";
import { logger } from "log";
import { publishMessageToStream } from "./service.js";
import { STREAM_APP_NAME, STREAM_NAME } from "./config.js";
export async function responseProvider(request) {
    /* For the demo moving authorization key into 'hidden' PM_user var.
    authorization should look like "apikey {some key}"
    */
    const authorizationHeader = `apikey ${request.getVariable("PMUSER_MM_APIKEY")}`;
    /*
    await our promise. This is the non streaming version, so there is this 128KB limitation. https://techdocs.akamai.com/edgeworkers/docs/limitations
    In the future we might change this one to a streaming interface but for now we're ok, demo only.
    Promise might be rejected because of empty or wrong request body, set it to null if so. (thanks chatgpt for this Nullish Coalescing advise, looks nice ;-)
    */
    let body = await request.json().catch(() => null);
    let result = {};
    let status = 200;
    // let's check if all the required elements are available in the body
    // And we're only interested in SMS messages
    if (body["user_id"] &&
        body["auth_type"] &&
        body["url_path"] &&
        body["auth_type"].toLowerCase() === "sms") {
        body["user_id_sha"] = await generateDigest("SHA-256", body.user_id);
        //logger.log(`user_id_sha: ${JSON.stringify(body["user_id_sha"])}`);
        // now send request to Macrometa stream endpoint.
        try {
            const response = await publishMessageToStream(STREAM_APP_NAME, STREAM_NAME, authorizationHeader, body);
            // assign result from our request to result
            result = response;
        }
        catch (error) {
            // if we have an error, get some details about that error and assign to final result
            logger.log("Error occurred while executing edgeWorker", error.toString());
            // overwrite our default 200 status with the real error code or just 500.
            status = error.status || 500;
            // define our error object.
            let errorMessage = {};
            if (error.status) {
                const dbError = JSON.parse(error.message) || {};
                errorMessage.errorCode = dbError.code;
                errorMessage.errorMessage =
                    dbError.errorMessage || "Something went wrong";
                errorMessage.errorNum = dbError.errorNum;
            }
            else {
                errorMessage.errorMessage = error.toString() || "Something went wrong";
            }
            // assign it to our result var which will be send as JSON in the result
            result = errorMessage;
        }
    }
    else {
        result = { error: "user_id not in body or not an SMS auth_type" };
    }
    return Promise.resolve(createResponse(status, {
        "Content-Type": "application/json",
        "Content-Language": "en-US",
    }, JSON.stringify(result)));
}
/**
 * Generates the digest from a string using the provided algorithm
 * @param {('SHA-1'|'SHA-256'|'SHA-384'|'SHA-512')} algorithm - The algorithm to use, must be one of the following options ["SHA-1", "SHA-256", "SHA-384","SHA-512"]
 * @param {string} stringToDigest - a string to digest
 * @returns {string} returns the string value of the digest
 */
async function generateDigest(algorithm, stringToDigest) {
    // first convert the input string into a stream of UTF-8 bytes (Uint8Array)
    // Uint8Array is a TypedArray so an array-like object that stores 8-bit unsigned integers (bytes).
    // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/TypedArray
    // length of the array should be the exact same size as the length of the string.
    // https://techdocs.akamai.com/edgeworkers/docs/encoding
    const msgUint8 = new TextEncoder().encode(stringToDigest);
    // A digest is a short fixed-length value derived from some variable-length input.
    // Generate a digest of the given data using SHA256, response will be an Arraybuffer promise.
    // Arraybuffer serves as a raw binary data storage.
    const hashBuffer = await crypto.subtle.digest(algorithm, msgUint8);
    // convert the digest generate arraybuffer to a Uint8Array TypedArray
    // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/TypedArray
    const walkable = Array.from(new Uint8Array(hashBuffer));
    // walk through the array, convert to string and put into single var
    return walkable.map((b) => b.toString(16).padStart(2, "0")).join("");
}
