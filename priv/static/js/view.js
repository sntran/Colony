// The camera as numbers: where a point of the world is on the screen.
//
// The picture uses this file, and a test player with no browser uses it also: it tells
// which cells a person sees.

const normalize = (v) => {
  const length = Math.hypot(...v) || 1;
  return v.map((part) => part / length);
};
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

function perspective(fov, aspect, near, far) {
  const f = 1 / Math.tan(fov / 2);
  return [f / aspect, 0, 0, 0, 0, f, 0, 0, 0, 0, (far + near) / (near - far), -1, 0, 0, (2 * far * near) / (near - far), 0];
}

function multiply(a, b) {
  const out = new Float32Array(16);
  for (let column = 0; column < 4; column++) {
    for (let row = 0; row < 4; row++) {
      let sum = 0;
      for (let k = 0; k < 4; k++) sum += a[k * 4 + row] * b[column * 4 + k];
      out[column * 4 + row] = sum;
    }
  }
  return out;
}

// camera: { x, z, turn, height, distance, fov }. The camera looks at the point x, z on the
// ground from behind and above. `aspect` is the width of the screen divided by its height.
// Returns { matrix, eye, basis }.
export function viewOf(camera, aspect) {
  const eye = [camera.x - Math.sin(camera.turn) * camera.distance, camera.height, camera.z - Math.cos(camera.turn) * camera.distance];
  const forward = normalize([camera.x - eye[0], -eye[1], camera.z - eye[2]]);
  // A camera that looks straight down has no "up" from the sky: the north is up.
  const sky = Math.abs(forward[1]) > 0.999 ? [Math.sin(camera.turn), 0, Math.cos(camera.turn)] : [0, 1, 0];
  const right = normalize(cross(forward, sky));
  const up = cross(right, forward);
  const view = [
    right[0], up[0], -forward[0], 0,
    right[1], up[1], -forward[1], 0,
    right[2], up[2], -forward[2], 0,
    -dot(right, eye), -dot(up, eye), dot(forward, eye), 1,
  ];
  return {
    matrix: multiply(perspective(camera.fov, aspect, 0.5, camera.far || 140), view),
    eye,
    basis: { forward, right, up, tan: Math.tan(camera.fov / 2), aspect },
  };
}

// The place of a point of the world on the screen: [x, y] from -1 to 1 for a point on the
// screen, with y up. Null if the point is behind the camera.
export function project(matrix, x, y, z) {
  const m = matrix;
  const w = m[3] * x + m[7] * y + m[11] * z + m[15];
  if (w <= 0.01) return null;
  return [(m[0] * x + m[4] * y + m[8] * z + m[12]) / w, (m[1] * x + m[5] * y + m[9] * z + m[13]) / w];
}

// The camera of a player: it looks at the body from the south, and a small distance to
// the north of the body.
export const PLAYER_CAMERA = { turn: 0, height: 10, distance: 10, fov: (55 * Math.PI) / 180, ahead: 2.2 };
