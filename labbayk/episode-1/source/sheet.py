import sys,glob,os
from PIL import Image,ImageDraw
src,out,guides=sys.argv[1],sys.argv[2],sys.argv[3]=='1'
fs=sorted(glob.glob(src+'/t*.png'),key=lambda p:float(os.path.basename(p)[1:-4]))
W,H=360,640;cols=4;rows=(len(fs)+cols-1)//cols
sh=Image.new('RGB',(cols*W+(cols+1)*10,rows*(H+40)+10),'#888')
d=ImageDraw.Draw(sh)
for i,f in enumerate(fs):
    im=Image.open(f).convert('RGB')
    if guides:
        g=ImageDraw.Draw(im);g.rectangle([0,0,1079,250],outline='red',width=6);g.rectangle([0,1540,1079,1919],outline='red',width=6)
    im=im.resize((W,H));x=10+(i%cols)*(W+10);y=10+(i//cols)*(H+40)
    sh.paste(im,(x,y));d.text((x+4,y+H+8),os.path.basename(f)[1:-4]+' s',fill='white')
sh.save(out)
