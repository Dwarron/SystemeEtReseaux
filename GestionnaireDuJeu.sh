#!/bin/bash

partieFini=false		#boolean pour connaitre l'état de la partie
cartes=()			#tableau qui represente les cartes du jeu au départ
cartesManche=()			#tableau qui represente les cartes du jeu durant une manche
nbJoueurs=0			#nombre de joueurs
nbRobots=0			#nombre de robots
nbJoueursTotaux=0		#nombre de participant totaux
declare -i manche=0		#nombre de manche de la partie, declare en integer (afin dutiliser +=)
declare -i carteDistibue=0	#nombre de carte distribuer dans la partie
declare -i carteRestante=0	#nombre de carte restante dans une manche

initJoueurs()
{	
	#initialiser les joueurs
	echo Pour commencer, selectionner le nombre de joueur"("s")"  :
	read nbJoueurs
	
	for i in $(eval echo {1..$nbJoueurs});
	do	
		#faire des tests pour savoir si on est dans le cas ou il faut utiliser bash ou xterm
		gnome-terminal -e "bash -c './Joueurs.sh $i;$SHELL'"  #$i represente le numero du joueurs
		#ou
		#xterm -e /bin/bash -l -c './Joueurs.sh $i'		
	done
}

initRobots()
{
	#initialiser les robots
	echo Ensuite selectionner le nombre de robot"("s")" :
	read nbRobots
	
	#on ouvre des terminaux pour les robots mais tous est automatisé
	for i in $(eval echo {1..$nbRobots});
	do
		gnome-terminal -e "bash -c './Robots.sh $i;$SHELL'" 
	done
}

#methode qui remplie un tableau qui represente l'ensemble des cartes, de 1 a 100 au départ
remplieCartes()
{
	for i in {1..100};
	do	
		cartes+=($i)
		#echo ${cartes[$i-1]}
	done
}

#methode qui va distribuer les cartes du jeu au joueur(s) de la partie
distribueCartes()
{
	manche+=1 #a chaque fois les cartes vont etre distribuer on incremente le nombre de manche
	
	for i in $(eval echo {1..$nbJoueursTotaux});
	do
		echo "" > tmp/cartePartie
		echo Manche : $manche
		#manche permet de savoir combien de carte par participant il faut distribuer
		for j in $(eval echo {1..$manche}); 
		do
			if [ $carteDistibue -gt $((98)) ];
			then
				#envoyer ce message a tous les joueurs
				echo Trop de carte distribué, fin de la partie.
				partieFini=true
				#exit 1
			fi
				
			randomCarte=$(($RANDOM % $((99 - $carteDistibue)))) #indice d'une carte tiré au hasard
			
			#toutes les cartes de la manche courante
			cartesManche+=(${cartes[$randomCarte]})
			
			#stock les cartes au cout par cout dans un fichier temporaire
			echo ${cartes[$randomCarte]} >> tmp/cartePartie

			retireCarte $randomCarte

			carteDistibue+=1	
		done
		echo Cartes : ${cartesManche[*]}
		echo "Cartes pour le participant $i" | nc -l -p 9091 
		sleep 1 #laisse le temps au participants de recuperer les cartes dans le fichier
	done
	
	carteRestante=$(($nbJoueursTotaux * $manche))
}

#methode qui retire la carte envoyer au joueur du tableau des cartes 
#1-recuperer toutes les cartes apres cette indice dans un tableau temporaire
#2-supprimer toutes les cartes a partir de la carte a retirer
#3-concatener le début du tableau des cartes qui na pas changé avec le tableau temporaire 
retireCarte()
{
	carteRetirer=$1		 #indice de la carte a retirer 
	cartesTemp=()		 #tableau temporaire pour la concatenation
	
	#echo Indice de la carte a retirer: $carteRetirer correspond a la ${cartes[$carteRetirer]}
	
	unset cartesTemp #on vide le tableau de tout son contenue avant de le remplir

	#on recupere toutes les cartes apres celles envoyer au joueurs que l'on veut enlever du tableau
	for x in $(eval echo {$(($carteRetirer + 1))..$((99 - $carteDistibue))});
	do	
		cartesTemp+=(${cartes[$x]})	
	done
	
	#on retire toutes les cartes a partir de la cartes envoyer au joueur
	for y in $(eval echo {$carteRetirer..$((99 - $carteDistibue))});
	do	
		unset cartes[$y]
	done
	
	#concatene le debut de lancien tableau valide avec le tableau temporaire qui contient bonne valeur
	for z in $(eval echo {0..${#cartesTemp[*]}});
	do	
		cartes+=(${cartesTemp[$z]})	
	done
}

#methode qui envoie le top depart de la partie
topDepart()
{
	for i in $(eval echo {1..$nbJoueursTotaux});
	do
		echo "Vous avez recu le top depart." | nc localhost 9091
	done
}

#methode qui permet de traiter les informations recu par l'ensemble des joueurs
traitementManche()
{
	carteAJouer=100	#la carte la plus petite du paquet des cartes de la manche en cours
	carteCourante=0		#carte courante du joueur
	numParticipant=0	#numero du participant
	
	#on chercher la plus petite carte
	for i in $(eval echo {0..${#cartesManche[*]}});
	do	
		if [ "$carteAJouer" \< "${cartesManche[$i]}" ];
		then
			carteAJouer=${cartesManche[$i]}
		fi
	done
	
	echo "Attente de connexion d'un joueur" | nc -l -p 9091 
	carteCourante=$(cat tmp/carteAJouer)
	numParticipant=$(cat tmp/numJoueur)

	if (( "$carteCourante" == "$carteAJouer" ));
	then
		#on enleve la carte des cartes de la manche
		cartesManche=( ${cartesManche[*]/$carteCourante} )	
		
		#envoyer ce message a tous les joueurs/robots
		echo "Carte $carteCourante joué par le participant n°$numParticipant"
		
		carteRestante=$((carteRestante - 1))
	else 	
		echo Mauvaise carte ! Carte $carteCourante du joueur ???? > tmp/finGame
		#envoyer ce message a tous les joueurs
		#echo Mauvaise carte ! Carte $carteCourante du joueur ????
		partieFini=true
		#exit 1
	fi
}

#methode qui permet de faire tourner la partie tant qu'elle n'est pas finie
deroulementPartie()
{
	while [ $partieFini == "false" ]
	do
		#traite les informations de la partie
		traitementManche 
		
		#si les joueurs non plus de cartes on en redistribue
		if (( "$carteRestante" == 0 ));
		then
			unset cartesManche
			echo Resdistribuer > tmp/redistribuer
 			distribueCartes
 			echo "" > tmp/redistribuer
 		fi;
	done
}

#methode qui demarre la partie 
startGame()
{
	remplieCartes
	
	#initJoueurs
	initRobots
	
	nbJoueursTotaux=$(($nbJoueurs + $nbRobots))
	#echo Nous avons donc $nbJoueursTotaux participants pour cette partie
	
	#on distribue les cartes une premiere fois avant le top depart
	distribueCartes
	
	#envoie le top depart apres la distribution des cartes a tout les joueurs
	topDepart
	
	deroulementPartie
}

startGame

#methode qui permet quand la partie est finie decrire le classement sur un fichier
classementPartie()
{
	echo test
#Recevoir le nom et le prenom des joueurs pour stocker leurs infos 
#On peut utiliser le nombre de cartes distribué et le nombre de manche passé
#faire le classement des joueurs et ecrire le resultat sur un fichier
}
