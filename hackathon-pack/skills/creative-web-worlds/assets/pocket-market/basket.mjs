export const products = [
  {id:'peaches',name:'Sun peaches',detail:'Three ripe, local peaches',price:450,color:'#f77748'},
  {id:'bread',name:'Sunday loaf',detail:'One sourdough loaf',price:650,color:'#ca8b3b'},
  {id:'flowers',name:'Field flowers',detail:'A small seasonal bunch',price:900,color:'#e34a66'}
];
export function totalCents(basket){return products.reduce((sum,p)=>sum+p.price*(basket[p.id]||0),0);}
export function changeQuantity(basket,id,delta){
 if(!products.some(p=>p.id===id)||!Number.isInteger(delta)) throw new Error('Unknown product or invalid quantity change');
 return {...basket,[id]:Math.min(9,Math.max(0,(basket[id]||0)+delta))};
}
export function parseBudget(value){if(!/^\d+(\.\d{1,2})?$/.test(value))return null; const cents=Math.round(Number(value)*100);return cents>=100&&cents<=100000?cents:null;}
export const money=cents=>new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'}).format(cents/100);
export function listText(basket,budget){return ['Pocket Market · Shopping list',...products.filter(p=>basket[p.id]).map(p=>`${basket[p.id]} × ${p.name} — ${money(p.price* basket[p.id])}`),`Total: ${money(totalCents(basket))}`,`Budget: ${money(budget)}`,`Prices are sample prices. This is a list, not an order.`].join('\n');}
