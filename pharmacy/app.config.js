const { expo } = require("./app.json");
module.exports = {
  ...expo,
  experiments: { baseUrl: process.env.PHARMACY_BASE_PATH || "" },
};
