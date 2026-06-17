import express from "express";
import cors from "cors";
import { config } from "./config";
import { authMiddleware } from "./middleware/auth";
import { errorHandler } from "./middleware/errorHandler";
import healthRoutes from "./routes/health";
import hookRoutes from "./routes/hook";
import decisionRoutes from "./routes/decision";
import pairingRoutes from "./routes/pairing";
import eventsRoutes from "./routes/events";
import { decisionService } from "./services/decisionservice";
import { pairingService } from "./services/pairingservice";
import { logger } from "./utils/logger";

export function createApp() {
  const app = express();

  // Core middleware
  app.use(cors({
    origin: (origin, cb) => {
      // Allow same-origin (null) or any localhost origin. The bridge binds to
      // 127.0.0.1, so the only cross-origin callers are local pages and the
      // iOS app (URLSession sends no Origin header → null).
      if (!origin
          || origin.startsWith("http://localhost")
          || origin.startsWith("http://127.0.0.1")) {
        cb(null, true);
      } else {
        cb(new Error("Not allowed by CORS"));
      }
    },
  }));
  app.use(express.json());

  // Store services on app locals for route access if needed
  app.locals.decisionService = decisionService;
  app.locals.pairingService = pairingService;

  // Auth middleware (validates bearer tokens for non-public routes)
  app.use(authMiddleware);

  // Routes
  app.use("/health", healthRoutes);
  app.use("/hook", hookRoutes);
  app.use("/decisions", decisionRoutes);
  app.use("/pair", pairingRoutes);
  app.use("/events", eventsRoutes);

  // Pending requests status (authenticated)
  app.get("/pending", (req, res) => {
    const token = (req as any).authToken;
    if (!token || !pairingService.validateToken(token)) {
      res.status(401).json({ error: "Invalid or expired session token" });
      return;
    }
    res.json({ pending: decisionService.getPendingList() });
  });

  // Error handler
  app.use(errorHandler);

  return app;
}
