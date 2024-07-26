import { client } from './client.js';
import { logger } from 'log';

export const publishMessageToStream = async (
  appName,
  streamName,
  authorizationToken,
  params = {},
) => {
  let response;
  try {
    response = await client.publishMessageToStream(
      appName,
      streamName,
      authorizationToken,
      params,
    );

    if (!response.ok) throw new Error(await response.text());

    const { message } = await response.json();

    return message;
  } catch (error) {
    error.status = response.status;
    logger.log(`Failed to fetch ${appName}`, JSON.stringify(error));
    throw error;
  }
};
