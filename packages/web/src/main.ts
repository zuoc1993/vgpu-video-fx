import { startApp } from "./app.ts";
import "./styles.css";

const stop = await startApp();
window.addEventListener("beforeunload", () => stop());
