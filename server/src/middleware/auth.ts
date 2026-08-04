import type { NextFunction, Response } from 'express';
import jwt from 'jsonwebtoken';
import { config } from '../config.js';
import type { AuthedRequest } from '../types.js';
export function auth(req:AuthedRequest,res:Response,next:NextFunction){ const token=req.headers.authorization?.replace(/^Bearer /,''); if(!token) return res.status(401).json({error:'Authentication required'}); try { req.userId=(jwt.verify(token,config.JWT_SECRET) as {sub:string}).sub; next(); } catch { return res.status(401).json({error:'Session expired'}); } }
