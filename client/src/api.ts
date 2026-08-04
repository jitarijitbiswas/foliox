import { useStore } from './store';
const base=import.meta.env.VITE_API_URL??'';
export async function api<T>(path:string,options:RequestInit={}){const token=useStore.getState().token;const response=await fetch(`${base}${path}`,{...options,headers:{'content-type':'application/json',...(token?{authorization:`Bearer ${token}`}:{ }),...options.headers}});if(!response.ok){const body=await response.json().catch(()=>({error:'Request failed'}));throw new Error(body.error);}return response.status===204?undefined as T:response.json() as Promise<T>;}
