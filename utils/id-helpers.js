// To use this, just import this file and supply it with some web3 utils:
//     require("@gnosis.pm/conditional-tokens-contracts/utils/id-helpers")(web3.utils)

module.exports = function({ BN, toBN, soliditySha3 }) {
  function getConditionId(oracle, questionId, outcomeSlotCount) {
    return soliditySha3(
      { t: "address", v: oracle },
      { t: "bytes32", v: questionId },
      { t: "uint", v: outcomeSlotCount }
    );
  }

  const altBN128P = toBN(
    "21888242871839275222246405745257275088696311157297823662689037894645226208583"
  );
  const altBN128PRed = BN.red(altBN128P);
  const altBN128B = toBN(3).toRed(altBN128PRed);
  const zeroPRed = toBN(0).toRed(altBN128PRed);
  const onePRed = toBN(1).toRed(altBN128PRed);
  const twoPRed = toBN(2).toRed(altBN128PRed);
  const fourPRed = toBN(4).toRed(altBN128PRed);
  const oddToggle = toBN(1).ushln(254);

  function getCollectionId(conditionId, indexSet) {
    const initHash = soliditySha3(
      { t: "bytes32", v: conditionId },
      { t: "uint", v: indexSet }
    );
    const odd = "89abcdef".includes(initHash[2]);

    const x = toBN(initHash).toRed(altBN128PRed);

    let y, yy;
    do {
      x.redIAdd(onePRed);
      yy = x.redSqr();
      yy.redIMul(x);
      yy = yy.mod(altBN128P);
      yy.redIAdd(altBN128B);
      y = yy.redSqrt();
    } while (!y.redSqr().eq(yy));

    const ecHash = x.fromRed();
    if (odd) ecHash.ixor(oddToggle);
    return `0x${ecHash.toString(16, 64)}`;
  }

  function combineCollectionIds(collectionIds) {
    if (Array.isArray(collectionIds) && collectionIds.length === 0) {
      return `0x${"0".repeat(64)}`;
    }

    const points = collectionIds.map(id => {
      let x = toBN(id);
      if (x.eqn(0)) {
        // a zero collection ID represents EC group identity
        // which is the point at infinity
        // satisfying projective equation
        // Y^2 = X^3 + 3*Z^6, Z=0
        return [onePRed, onePRed, zeroPRed];
      }
      const odd = x.and(oddToggle).eq(oddToggle);
      if (odd) x.ixor(oddToggle);
      x = x.toRed(altBN128PRed);
      let y, yy;
      yy = x.redSqr();
      yy = yy.redMul(x); // this might be a BN.js bug workaround
      yy.redIAdd(altBN128B);
      y = yy.redSqrt();
      if (!y.redSqr().eq(yy))
        throw new Error(`got invalid collection ID ${id}`);
      if (odd !== y.isOdd()) y = y.redNeg();
      return [x, y];
    });

    const [X, Y, Z] = points.reduce(([X1, Y1, Z1], [x2, y2]) => {
      // https://www.hyperelliptic.org/EFD/g1p/auto-shortw-jacobian-0.html#addition-madd-2007-bl
      if (Z1 == null) {
        Z1 = onePRed;
      }

      if (Z1.eqn(0)) {
        return [x2, y2];
      }

      // source 2007 Bernstein--Lange
      // assume Z2=1

      // compute Z1Z1 = Z1^2
      const Z1Z1 = Z1.redSqr();
      // compute U2 = X2 Z1Z1
      const U2 = x2.redMul(Z1Z1);
      // compute S2 = Y2 Z1 Z1Z1
      const S2 = y2.redMul(Z1).redMul(Z1Z1);
      // compute H = U2-X1
      const H = U2.redSub(X1);
      // compute HH = H^2
      const HH = H.redSqr();
      // compute I = 4 HH
      const I = HH.redMul(fourPRed);
      // compute J = H I
      const J = H.redMul(I);
      // compute r = 2 (S2-Y1)
      const r = twoPRed.redMul(S2.redSub(Y1));
      // compute V = X1 I
      const V = X1.redMul(I);
      // compute X3 = r^2-J-2 V
      const X3 = r
        .redSqr()
        .redSub(J)
        .redSub(twoPRed.redMul(V));
      // compute Y3 = r (V-X3)-2 Y1 J
      const Y3 = r.redMul(V.redSub(X3)).redSub(twoPRed.redMul(Y1).redMul(J));
      // compute Z3 = (Z1+H)^2-Z1Z1-HH
      const Z3 = Z1.redAdd(H)
        .redSqr()
        .redSub(Z1Z1)
        .redSub(HH);

      return [X3, Y3, Z3];
    });

    let x, y;
    if (Z) {
      if (Z.eqn(0)) {
        return `0x${"0".repeat(64)}`;
      } else {
        const invZ = Z.redInvm();
        const invZZ = invZ.redSqr();
        const invZZZ = invZZ.redMul(invZ);
        x = X.redMul(invZZ);
        y = Y.redMul(invZZZ);
      }
    } else {
      x = X;
      y = Y;
    }

    const ecHash = x.fromRed();
    if (y.isOdd()) ecHash.ixor(oddToggle);
    return `0x${ecHash.toString(16, 64)}`;
  }

  function getPositionId(collateralToken, collectionId) {
    return soliditySha3(
      { t: "address", v: collateralToken },
      { t: "uint", v: collectionId }
    );
  }

  return {
    getConditionId,
    getCollectionId,
    combineCollectionIds,
    getPositionId
  };
};
