const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, GetCommand } = require("@aws-sdk/lib-dynamodb");

const client = DynamoDBDocumentClient.from(new DynamoDBClient({}));

exports.handler = async (event) => {
  const result = await client.send(
    new GetCommand({
      TableName: process.env.TABLE_NAME,
      Key: { Id: process.env.SEED_USER_ID },
    })
  );

  return {
    statusCode: 200,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message: "Hello World", name: result.Item?.Name }),
  };
};
