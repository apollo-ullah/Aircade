import dotenv from "dotenv";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { config, higgsfield } from "@higgsfield/client/v2";

const currentDirectory = dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: resolve(currentDirectory, "../.env.local"), quiet: true });

const credentials = process.env.HF_CREDENTIALS;

if (!credentials || !/^[^:\s]+:[^:\s]+$/.test(credentials)) {
  throw new Error(
    "HF_CREDENTIALS is missing or invalid. Enter it locally in server/.env.local as key-id:key-secret.",
  );
}

config({ credentials });

const result = await higgsfield.subscribe(
  "bytedance/seedance-2.5/text-to-video",
  {
    input: {
      prompt: "A cinematic scene at sunset",
      duration: 5,
      resolution: "720p",
      aspect_ratio: "16:9",
      output_format: "mp4",
      generate_audio: true,
    },
    withPolling: true,
  },
);

if ((result.status as string) === "canceled") {
  throw new Error("Higgsfield generation was canceled.");
}

if (result.status === "nsfw") {
  throw new Error("Higgsfield generation was stopped by moderation.");
}

if (result.status === "failed") {
  throw new Error("Higgsfield generation failed.");
}

if (result.status !== "completed") {
  throw new Error("Higgsfield generation ended without completing.");
}

const videoUrl = result.video?.url;

if (!videoUrl) {
  throw new Error("Higgsfield completed without returning a video URL.");
}

console.log(videoUrl);
