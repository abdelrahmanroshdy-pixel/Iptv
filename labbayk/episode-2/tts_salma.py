import asyncio, ssl, sys, edge_tts, edge_tts.communicate as c
c._SSL_CTX = ssl.create_default_context(cafile='/root/.ccr/ca-bundle.crt')
async def main(txt, out, rate):
    await edge_tts.Communicate(open(txt).read(), 'ar-EG-SalmaNeural', rate=rate).save(out)
asyncio.run(main(sys.argv[1], sys.argv[2], sys.argv[3]))
