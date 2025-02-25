import "dotenv/config";

import { createStakerNodes } from "./tasks/createStakerNodes";

async function runTasks() {
  await createStakerNodes(2);
}

runTasks();
