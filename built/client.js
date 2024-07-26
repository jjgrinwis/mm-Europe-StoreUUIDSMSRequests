import { httpRequest } from 'http-request';
import { C8_URL, FABRIC, MACROMETA_ORIGIN_NAME } from './config.js';

export const client = {
  publishMessageToStream: (
    appName,
    streamName,
    authorizationToken,
    payload,
  ) => {
    return httpRequest(
      `${C8_URL}/_fabric/${FABRIC}/_api/streamapps/http/${appName}/${streamName}`,
      {
        method: 'POST',
        headers: {
          authorization: authorizationToken,
          'Macrometa-Origin': MACROMETA_ORIGIN_NAME,
        },
        body: JSON.stringify(payload),
      },
    );
  },
};
