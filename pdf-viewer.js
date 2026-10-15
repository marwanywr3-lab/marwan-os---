import * as pdfjs from './pdf.mjs';
pdfjs.GlobalWorkerOptions.workerSrc=new URL('./pdf.worker.mjs',import.meta.url).href;
export async function openPDF({blob,attachment,item,db,dialog,onError,onSaved}){
 const doc=await pdfjs.getDocument({data:new Uint8Array(await blob.arrayBuffer()),isEvalSupported:false}).promise;
 let page=1,version=item.version,annotations=structuredClone(item.data.pdf_annotations||{}),strokes=[],current=null,rendering=false,dirty=false;
 dialog.innerHTML='<h2>عرض PDF والتعليق عليه</h2><div class="toolbar"><button id="pdf-prev">السابق</button><span id="pdf-page"></span><button id="pdf-next">التالي</button><button id="pdf-clear">مسح تعليقات الصفحة</button><button id="pdf-save" class="primary">حفظ التعليقات</button><button id="pdf-close">إغلاق</button></div><p class="muted">ارسم بالقلم أو اللمس. تُحفظ التعليقات في حسابك حسب الملف ورقم الصفحة، ولا تغيّر ملف PDF الأصلي.</p><div style="position:relative;max-width:100%;overflow:auto" id="pdf-stage"><canvas id="pdf-page-canvas" style="display:block;max-width:100%"></canvas><canvas id="pdf-ink" style="position:absolute;inset:0;width:100%;height:100%;touch-action:none"></canvas></div>';
 const $=s=>dialog.querySelector(s),base=$('#pdf-page-canvas'),ink=$('#pdf-ink'),ctx=ink.getContext('2d');
 const key=()=>attachment.id+':'+page;
 function draw(){ctx.clearRect(0,0,ink.width,ink.height);ctx.lineWidth=3;ctx.strokeStyle='#b13f32';ctx.lineCap='round';for(const stroke of strokes){ctx.beginPath();stroke.forEach(([x,y],i)=>i?ctx.lineTo(x*ink.width,y*ink.height):ctx.moveTo(x*ink.width,y*ink.height));ctx.stroke();}}
 async function render(){rendering=true;const p=await doc.getPage(page),v=p.getViewport({scale:1.3});base.width=ink.width=v.width;base.height=ink.height=v.height;await p.render({canvasContext:base.getContext('2d'),viewport:v}).promise;strokes=annotations[key()]||[];draw();$('#pdf-page').textContent=page+' / '+doc.numPages;$('#pdf-prev').disabled=page===1;$('#pdf-next').disabled=page===doc.numPages;rendering=false;}
 function point(e){const r=ink.getBoundingClientRect();return [(e.clientX-r.left)/r.width,(e.clientY-r.top)/r.height];}
 ink.onpointerdown=e=>{if(rendering)return;ink.setPointerCapture(e.pointerId);current=[point(e)];strokes.push(current);};ink.onpointermove=e=>{if(current){current.push(point(e));draw();}};ink.onpointerup=ink.onpointercancel=()=>{if(current){annotations[key()]=strokes;dirty=true;current=null;}};
 $('#pdf-prev').onclick=async()=>{if(page>1&&!rendering){page--;await render();}};$('#pdf-next').onclick=async()=>{if(page<doc.numPages&&!rendering){page++;await render();}};
 $('#pdf-clear').onclick=()=>{if(confirm('مسح تعليقات هذه الصفحة؟')){strokes=[];annotations[key()]=[];dirty=true;draw();}};
 $('#pdf-save').onclick=async()=>{try{const r=await db.from('items').update({data:{...item.data,pdf_annotations:annotations}}).eq('id',item.id).eq('version',version).select();if(r.error)throw r.error;if(!r.data.length)throw new Error('تغيرت الملاحظة على جهاز آخر؛ لم تُحفظ التعليقات.');version=r.data[0].version;dirty=false;onSaved();}catch(e){onError(e);}};
 $('#pdf-close').onclick=()=>{if(!dirty||confirm('إغلاق دون حفظ التعليقات؟'))dialog.close();};
 dialog.oncancel=e=>{if(dirty&&!confirm('إغلاق دون حفظ التعليقات؟'))e.preventDefault();};
 await render();
}
