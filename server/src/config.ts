import 'dotenv/config';
import { z } from 'zod';
export const config = z.object({ DATABASE_URL:z.string().min(1), JWT_SECRET:z.string().min(16), CLIENT_URL:z.string().default('http://localhost:5173'), PORT:z.coerce.number().default(4000) }).parse(process.env);
