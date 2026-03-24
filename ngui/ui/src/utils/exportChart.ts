const createPng = (canvases: HTMLCanvasElement[]): Promise<Blob | null> =>
  new Promise((resolve) => {
    if (canvases.length === 0) {
      resolve(null);
      return;
    }

    const bgCanvas = document.createElement("canvas"); // for white background in exported file
    const ctx = bgCanvas.getContext("2d");

    if (!ctx) {
      resolve(null);
      return;
    }

    // Filter out canvases with zero dimensions
    const validCanvases = canvases.filter((canvas) => canvas.width > 0 && canvas.height > 0);

    if (validCanvases.length === 0) {
      resolve(null);
      return;
    }

    bgCanvas.width = Math.max(...validCanvases.map((canvas) => canvas.width));
    bgCanvas.height = Math.max(...validCanvases.map((canvas) => canvas.height));

    ctx.fillStyle = "#ffffff";
    ctx.fillRect(0, 0, bgCanvas.width, bgCanvas.height);

    try {
      validCanvases.forEach((canvas) => {
        ctx.drawImage(canvas, 0, 0);
      });
    } catch (e) {
      // CORS or tainted canvas error
      resolve(null);
      return;
    }

    bgCanvas.toBlob((blob) => {
      resolve(blob);
    }, "image/png");
  });

export { createPng };
